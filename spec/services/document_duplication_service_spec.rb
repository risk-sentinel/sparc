require "rails_helper"

RSpec.describe DocumentDuplicationService do
  describe "ProfileDocument duplication" do
    let!(:source) do
      create(:profile_document, name: "MODERATE Baseline", baseline_level: "MODERATE", profile_version: "2.1")
    end

    let!(:control) do
      create(:profile_control, profile_document: source, control_id: "ac-1", title: "Access Control Policy", priority: "P1")
    end

    let!(:field) do
      create(:profile_control_field, profile_control: control, field_name: "description", field_value: "Test description")
    end

    it "creates a new document with 'Copy of' prefix" do
      copy = described_class.new(source).duplicate
      expect(copy.name).to eq("Copy of MODERATE Baseline")
    end

    it "resets the version field" do
      copy = described_class.new(source).duplicate
      expect(copy.profile_version).to be_nil
    end

    it "sets status to completed" do
      copy = described_class.new(source).duplicate
      expect(copy.status).to eq("completed")
    end

    it "deep-clones controls" do
      copy = described_class.new(source).duplicate
      expect(copy.profile_controls.count).to eq(1)
      expect(copy.profile_controls.first.control_id).to eq("ac-1")
      expect(copy.profile_controls.first.title).to eq("Access Control Policy")
    end

    it "deep-clones control fields" do
      copy = described_class.new(source).duplicate
      copied_control = copy.profile_controls.first
      expect(copied_control.profile_control_fields.count).to eq(1)
      expect(copied_control.profile_control_fields.first.field_value).to eq("Test description")
    end

    it "creates fully independent copies" do
      copy = described_class.new(source).duplicate
      expect(copy.id).not_to eq(source.id)
      expect(copy.profile_controls.first.id).not_to eq(control.id)
    end

    it "preserves baseline_level" do
      copy = described_class.new(source).duplicate
      expect(copy.baseline_level).to eq("MODERATE")
    end

    it "records copy metadata" do
      copy = described_class.new(source).duplicate
      expect(copy.import_metadata["copied_from"]).to eq(source.id)
      expect(copy.import_metadata["copied_at"]).to be_present
    end

    it "allows a custom name" do
      copy = described_class.new(source).duplicate(new_name: "Custom Name")
      expect(copy.name).to eq("Custom Name")
    end
  end

  describe "CdefDocument duplication" do
    let!(:source) do
      create(:cdef_document, name: "RHEL 8 STIG", cdef_type: "disa_stig", cdef_version: "1.5")
    end

    let!(:control) do
      create(:cdef_control, cdef_document: source, control_id: "V-230221", title: "RHEL 8 must implement NIST crypto", severity: "high")
    end

    let!(:field) do
      create(:cdef_control_field, cdef_control: control, field_name: "fix_text", field_value: "Configure crypto policy")
    end

    it "creates a new document with 'Copy of' prefix" do
      copy = described_class.new(source).duplicate
      expect(copy.name).to eq("Copy of RHEL 8 STIG")
    end

    it "resets the version field" do
      copy = described_class.new(source).duplicate
      expect(copy.cdef_version).to be_nil
    end

    it "deep-clones controls and fields" do
      copy = described_class.new(source).duplicate
      expect(copy.cdef_controls.count).to eq(1)

      copied_control = copy.cdef_controls.first
      expect(copied_control.control_id).to eq("V-230221")
      expect(copied_control.severity).to eq("high")
      expect(copied_control.cdef_control_fields.count).to eq(1)
      expect(copied_control.cdef_control_fields.first.field_value).to eq("Configure crypto policy")
    end

    it "preserves cdef_type" do
      copy = described_class.new(source).duplicate
      expect(copy.cdef_type).to eq("disa_stig")
    end
  end
end
