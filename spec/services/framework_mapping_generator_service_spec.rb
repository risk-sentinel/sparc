# frozen_string_literal: true

require "rails_helper"

RSpec.describe FrameworkMappingGeneratorService do
  let(:nist_catalog) { create(:control_catalog, name: "NIST SP 800-53 Rev 5") }

  # ── DISA STIG (CCI pivot) ──────────────────────────────────────────

  describe "DISA STIG via CCI" do
    let(:cdef_doc) do
      create(:cdef_document,
             name:      "RHEL 9 STIG v1r1",
             cdef_type: "disa_stig",
             import_metadata: { "title" => "RHEL 9 STIG" })
    end

    # CCI-000015 → ac-2.1, CCI-000225 → ac-6 (per full DISA CCI data)
    let!(:control_with_ccis) do
      create(:cdef_control,
             cdef_document:  cdef_doc,
             control_id:     "SV-257777",
             cci_references: "CCI-000015,CCI-000225")
    end

    let!(:control_no_ccis) do
      create(:cdef_control,
             cdef_document:  cdef_doc,
             control_id:     "SV-999999",
             cci_references: nil)
    end

    let(:service) { described_class.new(cdef_doc, nist_catalog) }

    describe "#preview" do
      it "returns mapped NIST controls for controls with known CCIs" do
        result = service.preview
        expect(result).to have_key("SV-257777")
        expect(result["SV-257777"]).to include("ac-2.1")
        expect(result["SV-257777"]).to include("ac-6")
      end

      it "excludes controls with no CCI references" do
        result = service.preview
        expect(result).not_to have_key("SV-999999")
      end
    end

    describe "#coverage_stats" do
      it "returns correct coverage percentages" do
        stats = service.coverage_stats
        expect(stats[:total]).to eq(2)
        expect(stats[:mapped]).to eq(1)
        expect(stats[:unmapped]).to eq(1)
        expect(stats[:coverage_pct]).to eq(50.0)
      end
    end

    describe "#generate!" do
      it "creates a ControlMapping with entries" do
        mapping = service.generate!

        expect(mapping).to be_persisted
        expect(mapping.name).to eq("RHEL 9 STIG v1r1 → NIST SP 800-53 Rev 5")
        expect(mapping.method_type).to eq("automation")
        expect(mapping.status).to eq("draft")
        expect(mapping.control_mapping_entries.count).to be >= 2
      end

      it "creates entries with correct source/target pairs" do
        mapping = service.generate!
        entries = mapping.control_mapping_entries

        sv_entries = entries.where(source_control_id: "SV-257777")
        target_ids = sv_entries.pluck(:target_control_id)
        expect(target_ids).to include("ac-2.1")
        expect(target_ids).to include("ac-6")
      end

      it "sets remarks indicating CCI pivot" do
        mapping = service.generate!
        entry = mapping.control_mapping_entries.find_by(target_control_id: "ac-2.1")
        expect(entry.remarks).to match(/CCI-000015/)
      end

      it "creates a source catalog for the STIG" do
        mapping = service.generate!
        expect(mapping.source_catalog.name).to eq("RHEL 9 STIG")
      end

      it "stores generation metadata" do
        mapping = service.generate!
        expect(mapping.metadata_extra["generator"]).to eq("FrameworkMappingGeneratorService")
        expect(mapping.metadata_extra["cdef_type"]).to eq("disa_stig")
        expect(mapping.metadata_extra["mapping_file"]).to eq("cci_to_nist")
      end

      it "deduplicates NIST controls when multiple CCIs map to the same control" do
        # CCI-000002, CCI-002107, CCI-003602 all map to ac-1-a-1.a; ensure no duplicates
        ctrl = create(:cdef_control,
                      cdef_document:  cdef_doc,
                      control_id:     "SV-111111",
                      cci_references: "CCI-000002,CCI-002107,CCI-003602")

        mapping = service.generate!
        ac1_entries = mapping.control_mapping_entries
                             .where(source_control_id: ctrl.control_id, target_control_id: "ac-1-a-1.a")
        expect(ac1_entries.count).to eq(1)
      end
    end
  end

  # ── CIS Benchmarks ─────────────────────────────────────────────────

  describe "CIS Benchmarks" do
    let(:cdef_doc) do
      create(:cdef_document,
             name:      "CIS Ubuntu 22.04 v1.0",
             cdef_type: "cis",
             import_metadata: { "title" => "CIS Ubuntu 22.04 Benchmark" })
    end

    let!(:cis_control) do
      create(:cdef_control,
             cdef_document: cdef_doc,
             control_id:    "xccdf_org.cisecurity.benchmarks_rule_5.2.1",
             group_id:      "xccdf_org.cisecurity.benchmarks_group_5.2.1")
    end

    let(:service) { described_class.new(cdef_doc, nist_catalog) }

    describe "#preview" do
      it "maps CIS section IDs to NIST controls" do
        result = service.preview
        key = cis_control.control_id
        expect(result).to have_key(key)
        expect(result[key]).to include("ac-3")
        expect(result[key]).to include("ac-6")
      end
    end

    describe "#generate!" do
      it "creates mapping entries for CIS controls" do
        mapping = service.generate!
        entries = mapping.control_mapping_entries

        expect(entries.count).to be >= 2
        expect(entries.pluck(:target_control_id)).to include("ac-3", "ac-6")
      end

      it "sets remarks indicating CIS section" do
        mapping = service.generate!
        entry = mapping.control_mapping_entries.first
        expect(entry.remarks).to match(/CIS 5\.2\.1/)
      end
    end
  end

  # ── SCAP/OVAL ──────────────────────────────────────────────────────

  describe "SCAP/OVAL" do
    let(:cdef_doc) do
      create(:cdef_document,
             name:      "SCAP RHEL 8 Content",
             cdef_type: "scap",
             import_metadata: { "title" => "RHEL 8 SCAP" })
    end

    let!(:scap_control) do
      ctrl = create(:cdef_control,
                    cdef_document: cdef_doc,
                    control_id:    "oval:ssg-installed_env_has_login_defs:def:1",
                    title:         "Ensure password expiration policy")
      create(:cdef_control_field,
             cdef_control: ctrl,
             field_name:   "check_system",
             field_value:  "http://oval.mitre.org/XMLSchema/oval-definitions-5")
      create(:cdef_control_field,
             cdef_control: ctrl,
             field_name:   "description",
             field_value:  "Check password configuration and auth settings")
      ctrl
    end

    let(:service) { described_class.new(cdef_doc, nist_catalog) }

    describe "#preview" do
      it "resolves SCAP controls via check system and keyword matching" do
        result = service.preview
        expect(result).to have_key(scap_control.control_id)
        expect(result[scap_control.control_id]).not_to be_empty
      end
    end

    describe "#generate!" do
      it "creates mapping entries for SCAP controls" do
        mapping = service.generate!
        expect(mapping.control_mapping_entries.count).to be >= 1
      end
    end
  end

  # ── Unsupported framework ──────────────────────────────────────────

  describe "unsupported framework" do
    let(:cdef_doc) { create(:cdef_document, cdef_type: "custom") }
    let(:service)  { described_class.new(cdef_doc, nist_catalog) }

    it "raises UnsupportedFramework on generate!" do
      expect { service.generate! }.to raise_error(
        FrameworkMappingGeneratorService::UnsupportedFramework, /custom/
      )
    end

    it "returns empty preview" do
      expect(service.preview).to be_empty
    end
  end
end
