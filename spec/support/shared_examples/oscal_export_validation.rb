# frozen_string_literal: true

# #989 — the contract every OSCAL export service signs up to.
#
# Eight services expose BOTH `#export` (schema-validated) and
# `#export_unvalidated` (no validation). Four of them — SAP, SAR, catalog and
# mapping — had specs that never called the validated method once, so the
# schema-validation guarantee was untested on those paths. Nothing was broken:
# all four succeeded when measured. That is precisely the risk. A guarantee no
# test asserts is one a regression can remove silently.
#
# ── The worked example ─────────────────────────────────────────────────────
#
# #988. `oscal_ssp_export_inheritance_spec.rb` asserted the SSP's
# `leveraged-authorizations` array through `export_unvalidated` only. A
# `LeveragedAuthorization` with no `date_authorized` produced an entry missing an
# OSCAL-required property, and the spec passed — because it checked the SHAPE of
# the field it cared about — while the whole suite stayed green, because nothing
# exercised the validated path. It surfaced on a real deployment, as every SSP
# export bouncing to `?oscal_validation_failed=1`.
#
# `export_unvalidated` proves a document has the right shape.
# `export` proves it is a legal OSCAL document.
# Asserting only the first is how a structurally-plausible, schema-invalid
# artifact ships.
#
# ── Both paths are preserved, deliberately ─────────────────────────────────
#
# This does NOT replace `export_unvalidated` coverage and must not be used to.
# The two methods exist for different jobs: `export_unvalidated` is the right
# tool for asserting one field's shape without paying for schema validation, and
# for callers that skip validation on purpose. What these examples add is proof
# that the two are actually different, so neither can quietly become the other.
#
# ── Usage ──────────────────────────────────────────────────────────────────
#
#   it_behaves_like "an OSCAL export with validated and unvalidated paths",
#     model_type: :catalog,
#     service: -> { described_class.new(catalog) }
#
# `model_type` is the symbol the service passes to
# `OscalSchemaValidationService.validate!` — asserting it means a service cannot
# validate its output against the WRONG schema and still pass.
RSpec.shared_examples "an OSCAL export with validated and unvalidated paths" do |model_type:, service:|
  let(:export_service) { instance_exec(&service) }

  describe "#export — the validated path (#989)" do
    it "produces schema-valid OSCAL for a well-formed record" do
      expect { export_service.export }.not_to raise_error
    end

    it "validates against the #{model_type} schema, not merely some schema" do
      allow(OscalSchemaValidationService).to receive(:validate!).and_call_original

      export_service.export

      expect(OscalSchemaValidationService)
        .to have_received(:validate!).with(model_type, anything, hash_including(:version))
    end

    # The alerting half. An export that cannot produce a legal document must
    # REFUSE, not hand back a payload — that refusal is what the UI turns into
    # `?oscal_validation_failed=1` rather than shipping a bad artifact.
    #
    # The validator is stubbed rather than fed a hand-broken document: what is
    # under test here is that this service PROPAGATES the alert. Whether the
    # validator itself detects a given defect is
    # oscal_schema_validation_service_spec's job, and duplicating it per service
    # would test the schema eight times and the propagation never.
    it "raises rather than returning a payload when validation fails" do
      allow(OscalSchemaValidationService).to receive(:validate!)
        .and_raise(OscalValidationError, "OSCAL #{model_type} validation failed:\nsynthetic")

      expect { export_service.export }.to raise_error(OscalValidationError, /synthetic/)
    end
  end

  describe "#export_unvalidated — the unvalidated path (#989)" do
    it "returns parseable JSON" do
      expect { JSON.parse(export_service.export_unvalidated) }.not_to raise_error
    end

    # The assertion that keeps the two methods honest. If this ever fails,
    # `export_unvalidated` has started validating and the cheap path is gone; if
    # the validated examples above fail while this passes, validation has been
    # dropped from `export`. Neither can drift into the other unnoticed.
    it "does not validate, which is the whole reason it exists" do
      allow(OscalSchemaValidationService).to receive(:validate!).and_call_original

      export_service.export_unvalidated

      expect(OscalSchemaValidationService).not_to have_received(:validate!)
    end

    it "still returns a payload when validation would have refused one" do
      allow(OscalSchemaValidationService).to receive(:validate!)
        .and_raise(OscalValidationError, "synthetic")

      expect(export_service.export_unvalidated).to be_present
    end
  end
end
