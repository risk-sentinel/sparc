# frozen_string_literal: true

require "rails_helper"

# #911 layer 2 — SPARC must not publish OSCAL naming controls that exist in no
# loaded catalog.
#
# The schema cannot catch this. `control-id` is TokenDatatype, which constrains
# the character set and says nothing about existence, so a spreadsheet's "TBD"
# canonicalises to `tbd` — a perfectly legal token — and every downstream
# consumer accepts an implemented requirement against a control that does not
# exist.
RSpec.describe "OSCAL export refuses unresolvable control ids" do
  let(:catalog) { create(:control_catalog) }
  let(:family) { create(:control_family, control_catalog: catalog) }
  let(:profile) { create(:profile_document, control_catalog: catalog) }
  let(:ssp) { create(:ssp_document, profile_document: profile, name: "Acme SSP") }

  before { create(:catalog_control, control_family: family, control_id: "ac-2") }

  describe "the laundering the schema lets through" do
    # Documented as measured input, so the reason this guard exists cannot be
    # lost: these are all schema-valid.
    {
      "TBD"            => "tbd",
      "See note"       => "see-note",
      "Not applicable" => "not-applicable"
    }.each do |raw, canonical|
      it "treats #{raw.inspect} as unresolvable even though #{canonical.inspect} is a legal token" do
        expect(ControlId.token?(canonical)).to be(true), "precondition: the schema would accept this"

        create(:ssp_control, ssp_document: ssp, control_id: raw)

        expect { OscalSspExportService.new(ssp).export }
          .to raise_error(OscalValidationError, /exist in no loaded catalog/)
      end
    end
  end

  describe "refusing" do
    it "names the offending identifiers so the author can find them" do
      create(:ssp_control, ssp_document: ssp, control_id: "ac-2")
      create(:ssp_control, ssp_document: ssp, control_id: "zz-99")

      expect { OscalSspExportService.new(ssp).export }
        .to raise_error(OscalValidationError, /zz-99/)
    end

    it "carries the remedy" do
      create(:ssp_control, ssp_document: ssp, control_id: "zz-99")

      expect { OscalSspExportService.new(ssp).export }
        .to raise_error(OscalValidationError, /Load the catalog or profile/)
    end

    # Refuse, don't omit: the row is a control its author intended to claim, and
    # an incomplete SSP presented as complete is a false assurance.
    it "does not quietly drop the row and export the rest" do
      create(:ssp_control, ssp_document: ssp, control_id: "ac-2")
      create(:ssp_control, ssp_document: ssp, control_id: "zz-99")

      expect { OscalSspExportService.new(ssp).export }.to raise_error(OscalValidationError)
    end
  end

  describe "not refusing" do
    it "exports when every control resolves" do
      create(:ssp_control, ssp_document: ssp, control_id: "AC-02")  # padded spelling

      expect { OscalSspExportService.new(ssp).export }.not_to raise_error
    end

    it "accepts any legitimate spelling, since resolution is canonical" do
      create(:ssp_control, ssp_document: ssp, control_id: "ac-2")

      expect { OscalSspExportService.new(ssp).export }.not_to raise_error
    end

    # Shared-responsibility rows legitimately carry no control id. They are not
    # unresolvable references — there is no reference.
    it "ignores rows with no control id at all" do
      create(:ssp_control, ssp_document: ssp, control_id: "ac-2")
      create(:ssp_control, ssp_document: ssp, control_id: nil,
             title: "Cloud Provider — Network Bound")

      expect { OscalSspExportService.new(ssp).export }.not_to raise_error
    end
  end

  # A document with hundreds of controls must not turn into hundreds of queries.
  # `CatalogControl.resolvable?` per row would make an export a round trip per
  # control, which is why resolution is batched.
  it "resolves the whole document in a bounded number of queries" do
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      described = Class.new { include OscalExportReconciliation }.new
      described.send(:unresolvable_control_ids, Array.new(50) { "ac-2" })
    end

    expect(queries).to be <= 2, "resolution must not be per-control"
  end
end
