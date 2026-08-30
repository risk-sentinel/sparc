# frozen_string_literal: true

require "rails_helper"

# #968 — the #963 audit, applied to the one site it never reached.
#
# `upsert_leveraged_authorization_record` rescues RecordNotUnique, and did so
# with NO SAVEPOINT while running inside `parse_from_hash`'s transaction. That is
# the #963 shape exactly: Postgres aborts the whole transaction on the failed
# statement, so the rescue does not skip the row — it kills the import, and
# `parse_control_implementation`, which runs AFTER the leveraged-authorization
# pass in the same transaction, raises InFailedSqlTransaction.
#
# Reachable by construction: `leveraged_authorizations.uuid` has presence and
# format validations but NO Rails uniqueness validation, while the table carries
# a unique index (`index_leveraged_authorizations_on_uuid`). A duplicate
# therefore passes Ruby validation and fails in the DATABASE — which is the
# class of error that aborts a transaction. RecordInvalid would not.
#
# `claimable_leveraged_authorization_uuid` normally mints a fresh uuid when the
# imported one is taken, so the mitigation is stubbed to hand back the colliding
# value. That is deliberate: the subject here is the rescue's transaction
# safety, not the uuid-claiming logic, and stubbing the mitigation is what makes
# the guarded path reachable at all.
RSpec.describe SspJsonParserService, "leveraged-authorization savepoint (#968)" do
  let(:document)       { create(:ssp_document, name: "savepoint probe", status: "processing") }
  let(:colliding_uuid) { SecureRandom.uuid }
  let!(:existing)      { create(:leveraged_authorization, uuid: colliding_uuid) }

  let(:payload) do
    {
      "system-security-plan" => {
        "uuid" => SecureRandom.uuid,
        "metadata" => { "title" => "Probe", "version" => "1.0",
                        "oscal-version" => "1.1.2", "last-modified" => Time.current.iso8601 },
        "system-implementation" => {
          "leveraged-authorizations" => [ {
            "uuid" => colliding_uuid, "title" => "Colliding leveraged system",
            "party-uuid" => SecureRandom.uuid, "date-authorized" => "2026-01-01"
          } ],
          "components" => []
        },
        "control-implementation" => {
          "description" => "probe",
          "implemented-requirements" => [
            { "uuid" => SecureRandom.uuid, "control-id" => "ac-1" },
            { "uuid" => SecureRandom.uuid, "control-id" => "ac-2" }
          ]
        }
      }
    }
  end

  subject(:parser) { described_class.new(document, nil) }

  before do
    # Force the DB-level collision the savepoint exists to survive.
    allow(parser).to receive(:claimable_leveraged_authorization_uuid).and_return(colliding_uuid)
  end

  it "still imports the controls that come AFTER the collision" do
    expect { parser.send(:parse_from_hash, payload) }.not_to raise_error

    # THE POINT. control-implementation is parsed after the
    # leveraged-authorization pass, inside the same transaction. Unguarded, the
    # collision aborts that transaction and these never land — while the rescue
    # swallows and the caller returns as though the import succeeded.
    expect(document.reload.ssp_controls.pluck(:control_id)).to match_array(%w[ac-1 ac-2]),
      "controls parsed after the collision are missing — the transaction was " \
      "poisoned by a rescue with no SAVEPOINT (#963/#968)"
  end

  it "leaves the connection usable rather than in a failed transaction" do
    parser.send(:parse_from_hash, payload)

    # InFailedSqlTransaction surfaces on the NEXT statement, not at the rescue,
    # which is why "no exception was raised" is not sufficient evidence.
    expect { SspDocument.count }.not_to raise_error
  end

  it "does not write a duplicate row for the colliding uuid" do
    parser.send(:parse_from_hash, payload)

    expect(LeveragedAuthorization.where(uuid: colliding_uuid).count).to eq(1)
  end
end
