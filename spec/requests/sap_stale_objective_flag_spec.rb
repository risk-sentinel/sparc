# frozen_string_literal: true

require "rails_helper"

# A SAP or SAR generated before its baseline resolved is flagged
# "needs_reassociation" and gets no 800-53A objectives. Nothing cleared the flag
# once the baseline was published or linked, so the screen kept saying "isn't
# linked to a profile" beside a linked one, with no objectives (owner testing,
# v1.17.5). Opening it now backfills the objectives when the catalog resolves.
RSpec.describe "A stale per-objective flag", type: :request do
  let(:catalog) do
    { "catalog" => { "uuid" => SecureRandom.uuid,
                     "metadata" => { "title" => "Moderate", "version" => "1", "oscal-version" => "1.1.2",
                                     "last-modified" => Time.current.iso8601 },
                     "groups" => [ { "id" => "ac", "class" => "family", "title" => "Access Control",
                                     "controls" => [ { "id" => "ac-2", "class" => "SP800-53", "title" => "Account Management",
                                                       "parts" => [ { "id" => "ac-2_obj", "name" => "assessment-objective",
                                                                      "parts" => [ { "id" => "ac-2_obj.a", "name" => "assessment-objective",
                                                                                     "props" => [ { "name" => "label", "value" => "AC-02a." } ],
                                                                                     "prose" => "account types are defined" } ] } ] } ] } ] } }
  end
  let(:flag) { { ControlObjectiveExtractorService::REASSOCIATION_FLAG => ControlObjectiveExtractorService::REASSOCIATION_VALUE } }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(create(:user, :admin))
  end

  def sap_with(profile)
    create(:sap_document, status: "completed", profile_document: profile, import_metadata: flag).tap do |sap|
      sap.sap_controls.create!(control_id: "ac-2", title: "Account Management", row_order: 0)
    end
  end

  it "backfills the objectives and drops the banner once the baseline resolves" do
    sap = sap_with(create(:profile_document, lifecycle_status: "published", resolved_catalog_json: catalog))

    get sap_document_path(sap)

    expect(response.body).not_to include("Per-objective tracking unavailable")
    expect(response.body).to include("account types are defined")
    expect(sap.reload.import_metadata).not_to have_key(ControlObjectiveExtractorService::REASSOCIATION_FLAG)
    expect(sap.sap_controls.first.sap_control_objectives.pluck(:objective_id)).to include("ac-2_obj.a")
  end

  it "keeps the banner while nothing resolves" do
    sap = sap_with(nil)

    get sap_document_path(sap)

    expect(response.body).to include("Per-objective tracking unavailable")
    expect(sap.reload.import_metadata).to include(flag)
  end

  it "repairs a SAR the same way" do
    profile = create(:profile_document, lifecycle_status: "published", resolved_catalog_json: catalog)
    sar = create(:sar_document, status: "completed", profile_document: profile, import_metadata: flag)
    sar.sar_controls.create!(control_id: "ac-2", title: "Account Management", row_order: 0)

    get sar_document_path(sar)

    expect(response.body).not_to include("Per-objective tracking unavailable")
    expect(sar.sar_controls.first.sar_control_objectives.pluck(:objective_id)).to include("ac-2_obj.a")
  end
end
