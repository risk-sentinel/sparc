# frozen_string_literal: true

require "rails_helper"

# #1368 — every value DispositionVocabulary uses is NIST's or HDF's, checked
# against the sources rather than against itself: the committed OSCAL v1.2.3
# schema (lib/oscal_schemas/), and fixtures extracted verbatim from NIST's v1.2.3 metaschema and
# hdf-libs v3.8.0's amendments schema (each records its source and checksum).
RSpec.describe DispositionVocabulary do
  let(:fixtures) { Rails.root.join("spec/fixtures/files/vocabularies") }
  let(:nist) { JSON.parse(fixtures.join("nist_oscal_v1.2.3_poam_risk.json").read) }
  let(:hdf) { JSON.parse(fixtures.join("hdf_v3.8.0_amendments.json").read) }
  let(:oscal_poam_schema) do
    # The committed v1.2.3 schema (lib/oscal_schemas_bundle/ is generated, and
    # absent on CI).
    JSON.parse(Rails.root.join("lib/oscal_schemas/oscal_poam_schema.json").read)["definitions"]
  end

  def schema_enum(definition)
    Array(oscal_poam_schema.fetch(definition)["anyOf"]).find { |branch| branch["enum"] }&.fetch("enum")
  end

  describe "against NIST OSCAL v1.2.3" do
    it "uses NIST's risk statuses, which the vendored schema carries too" do
      expect(described_class::RISK_STATUSES).to eq(nist["risk_status"])
      expect(described_class::RISK_STATUSES).to eq(schema_enum("oscal-poam-oscal-assessment-common:risk-status"))
    end

    it "uses NIST's response lifecycles" do
      expect(described_class::RESPONSE_LIFECYCLES).to eq(nist["response_lifecycle"])
    end

    it "offers NIST's risk props except priority, which is a number, not a disposition" do
      expect(described_class::RISK_PROPS).to eq(nist["risk_prop_names"] - %w[priority])
    end

    it "uses NIST's response types, risk-log entry types and facet states" do
      expect(described_class::RESPONSE_TYPES).to eq(nist["response_type"])
      expect(described_class::RISK_LOG_ENTRY_TYPES).to eq(nist["risk_log_entry_type"])
      expect(described_class::FACET_STATES).to eq(nist["facet_state"])
    end

    it "writes only facet names NIST defines in its own namespace" do
      expect(%w[likelihood impact risk]).to all(be_in(nist["nist_facet_names"]))
      expect(described_class::NIST_FACET_SYSTEM).to eq("http://csrc.nist.gov/ns/oscal")
    end
  end

  describe "against HDF v3.8.0" do
    it "names HDF's override types" do
      expect(described_class::HDF_OVERRIDE_TYPES).to eq(hdf["override_type"])
    end

    it "maps every kind to a valid HDF override type" do
      described_class::MAPPINGS.each do |kind, mapping|
        expect(hdf["override_type"]).to include(mapping.hdf_override_type), kind
      end
    end

    it "treats vendorDependency as the HDF POA&M type it is, exported as a poam override" do
      expect(hdf["poam_type"]).to include("vendorDependency")
      expect(hdf["override_type"]).not_to include("vendorDependency")
      expect(described_class.for("vendorDependency").hdf_override_type).to eq("poam")
    end
  end

  describe "the mapping table (owner, 2026-11-18)" do
    it "maps each kind to a NIST response type and risk-log type" do
      described_class::MAPPINGS.each do |kind, mapping|
        expect(described_class::RESPONSE_TYPES).to include(mapping.response_type), kind
        next if mapping.risk_log == described_class::DEVIATION_LOG

        expect(described_class::RISK_LOG_ENTRY_TYPES).to include(mapping.risk_log), kind
      end
    end

    it "says vendor dependency is a transfer, logged as a vendor check-in" do
      expect(described_class.for("vendorDependency")).to have_attributes(response_type: "transfer", risk_log: "vendor-check-in")
    end

    it "logs a deviation by its approval" do
      expect(described_class.risk_log_types("waiver", "draft")).to eq(%w[dr-submission])
      expect(described_class.risk_log_types("waiver", "approved")).to eq(%w[dr-submission dr-approved])
      expect(described_class.risk_log_types("falsePositive", "rejected")).to eq(%w[dr-submission dr-rejected])
      expect(described_class.risk_log_types("poam", "approved")).to eq(%w[status-update])
    end

    it "covers every disposition kind" do
      expect(described_class::KINDS).to match_array(FindingDisposition::KINDS)
    end
  end

  # NIST SP 800-30 Rev. 1, Table I-2, read from the published PDF.
  describe "SP 800-30 risk levels" do
    it "uses SPARC's one five-level scale" do
      expect(described_class::LEVELS).to eq(RiskRating::LEVELS)
      expect(described_class::LEVELS).to eq(%w[very-low low moderate high very-high])
    end

    it "derives risk from likelihood and impact as Table I-2 does" do
      expect(described_class.risk_level("very-high", "very-high")).to eq("very-high")
      expect(described_class.risk_level("moderate", "high")).to eq("moderate")
      expect(described_class.risk_level("moderate", "very-high")).to eq("high")
      expect(described_class.risk_level("low", "high")).to eq("low")
      expect(described_class.risk_level("low", "very-high")).to eq("moderate")
      expect(described_class.risk_level("very-low", "high")).to eq("low")
      expect(described_class.risk_level("very-low", "moderate")).to eq("very-low")
      expect(described_class.risk_level("high", "very-low")).to eq("very-low")
    end

    it "has a full row for every likelihood" do
      expect(described_class::RISK_TABLE.keys).to match_array(described_class::LEVELS)
      expect(described_class::RISK_TABLE.values).to all(have_attributes(size: 5))
      expect(described_class::RISK_TABLE.values.flatten).to all(be_in(described_class::LEVELS))
    end
  end
end
