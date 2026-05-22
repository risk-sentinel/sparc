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

    # Issue #519 — statements were silently dropped during copy prior to the
    # DocumentDuplicationService refactor that added the optional statements
    # association. AWS Labs CDEFs (which always carry implemented-requirement
    # statements per OSCAL component-definition) lost them on the user's
    # clone, masking related downstream failures.
    describe "statement copying (#519)" do
      let!(:statement) do
        control.cdef_control_statements.create!(
          statement_id: "smt.a",
          implementation_prose: "Statement prose body",
          uuid: SecureRandom.uuid
        )
      end

      it "deep-clones cdef_control_statements onto the copy" do
        copy = described_class.new(source).duplicate
        copied_control = copy.cdef_controls.first
        expect(copied_control.cdef_control_statements.count).to eq(1)
        expect(copied_control.cdef_control_statements.first.statement_id).to eq("smt.a")
        expect(copied_control.cdef_control_statements.first.implementation_prose).to eq("Statement prose body")
      end

      it "gives copied statements fresh UUIDs (uuid is globally unique)" do
        copy = described_class.new(source).duplicate
        copied_stmt = copy.cdef_controls.first.cdef_control_statements.first
        expect(copied_stmt.uuid).to be_present
        expect(copied_stmt.uuid).not_to eq(statement.uuid)
      end

      it "preserves the statement_id under the new control_id (uniqueness scope)" do
        copy = described_class.new(source).duplicate
        copied_stmt = copy.cdef_controls.first.cdef_control_statements.first
        expect(copied_stmt.cdef_control_id).to eq(copy.cdef_controls.first.id)
        expect(copied_stmt.cdef_control_id).not_to eq(control.id)
      end
    end

    describe "AWS-Labs-sourced CDEF copy (#519)" do
      before do
        source.update!(import_metadata: {
          "source_type" => "aws_labs",
          "source_url"  => "https://example.invalid/iam.oscal.json",
          "source_sha"  => "deadbeef"
        })
        control.cdef_control_statements.create!(
          statement_id: "smt.a",
          implementation_prose: "Statement prose",
          uuid: SecureRandom.uuid
        )
        # Enrichment-style fields added by AwsLabsCdefImportService#enrich_with_nist_mappings!
        control.cdef_control_fields.create!(field_name: "aws_security_hub_id",  field_value: "IAM.1", editable: false)
        control.cdef_control_fields.create!(field_name: "nist_oscal_ids",       field_value: "ac-2,ac-3", editable: false)
        control.cdef_control_fields.create!(field_name: "nist_mapping_source",  field_value: "aws_direct", editable: false)
      end

      it "duplicates without raising and preserves statements + enrichment fields" do
        expect { described_class.new(source).duplicate }.not_to raise_error

        copy = described_class.new(source).duplicate(new_name: "Copy of #{source.name}-2")
        copied_control = copy.cdef_controls.first
        expect(copied_control.cdef_control_statements.count).to eq(1)
        # 1 fix_text from the parent let! block + 3 enrichment fields = 4
        expect(copied_control.cdef_control_fields.count).to eq(4)
      end

      it "strips the source_type from the copy's import_metadata so it isn't read-only" do
        copy = described_class.new(source).duplicate
        expect(copy.import_metadata["source_type"]).to be_nil
        expect(copy.aws_labs_source?).to be false
        expect(copy.editable?).to be true
      end
    end
  end
end
