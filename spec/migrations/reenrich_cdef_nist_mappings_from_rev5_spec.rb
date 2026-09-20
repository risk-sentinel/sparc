# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260920120000_reenrich_cdef_nist_mappings_from_rev5.rb")

# #1103 — existing deployments carry rev4 NIST ids in a converter declared rev5,
# and cannot pick up the re-vendored coverage because db/seeds/converters.rb only
# loads entries when the converter has none.
RSpec.describe ReenrichCdefNistMappingsFromRev5 do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  around do |example|
    DeferredDataMigration.executing!
    example.run
  ensure
    DeferredDataMigration.idle!
  end

  let!(:sec_hub_converter) do
    create(:converter, converter_type: "aws_security_hub_to_nist",
                       source_framework: "AWS Security Hub", status: "complete")
  end

  let!(:aws_config_converter) do
    create(:converter, converter_type: "aws_config_to_nist",
                       source_framework: "AWS Config Rules", status: "complete")
  end

  let(:document) { create(:cdef_document, file_type: "json") }

  # A control as it exists on a deployment that ran the OLD pipeline: the
  # Security Hub id preserved as provenance, and a rev4 statement-letter id
  # sitting in control_id as though it were rev5.
  def stale_control!(sec_hub_id: "IAM.7", control_id: "ac-2_smt.j")
    control = document.cdef_controls.create!(
      title: "t", control_id: control_id, control_family: "AC",
      source_control_id: sec_hub_id, source_vocabulary: "aws_security_hub"
    )
    control.cdef_control_fields.create!(field_name: "nist_mapping_source",
                                        field_value: "via_config_rule", editable: false)
    control.cdef_control_fields.create!(field_name: "nist_oscal_ids",
                                        field_value: control_id, editable: false)
    control
  end

  # The rev4 row a pre-#1103 instance would be holding.
  def seed_stale_config_entry!
    ConverterEntry.create!(
      converter: aws_config_converter, source_id: "iam-password-policy",
      target_id: "ac-2_smt.j", relationship: "intersects",
      category: "mitre_vendored", row_order: 1
    )
  end

  describe "converter reload" do
    it "replaces the vendored rows with the shipped file's, and declares its revision" do
      seed_stale_config_entry!

      migration.up

      aws_config_converter.reload
      expect(aws_config_converter.target_rev).to eq("5")
      expect(aws_config_converter.converter_entries.where(category: "mitre_vendored").count).to be > 100
      # The rev4 statement-letter target is gone from the vendored rows.
      expect(
        aws_config_converter.converter_entries.where(category: "mitre_vendored").pluck(:target_id)
      ).to all(satisfy { |id| !id.include?("_smt.") })
    end

    # The whole reason the refresh service scopes its delete by category.
    it "leaves operator-added rows alone" do
      hand_added = ConverterEntry.create!(
        converter: aws_config_converter, source_id: "our-own-rule",
        target_id: "cm-6", relationship: "intersects",
        category: "custom", row_order: 9999
      )

      migration.up

      expect(ConverterEntry.exists?(hand_added.id)).to be(true)
    end

    it "reloads the Security Hub converter from its shipped file too" do
      migration.up

      expect(sec_hub_converter.reload.converter_entries.where(category: "aws_direct").count).to be > 100
    end

    it "does not blank a converter when the vendored file is missing" do
      seed_stale_config_entry!
      allow(File).to receive(:read).and_call_original
      stub_const("#{described_class}::MAPPINGS_DIR", Rails.root.join("lib/data_mappings/nope"))

      migration.up

      expect(aws_config_converter.converter_entries.count).to eq(1)
    end

    it "is a no-op for a converter this instance never seeded" do
      aws_config_converter.destroy!

      expect { migration.up }.not_to raise_error
    end
  end

  describe "re-enrichment" do
    it "replaces a rev4 statement-letter id with the rev5 mapping" do
      control = stale_control!

      migration.up

      control.reload
      expect(control.control_id).not_to include("_smt.")
      expect(control.control_id).to be_present
      expect(control.source_control_id).to eq("IAM.7")
    end

    it "keeps the Security Hub identifier as provenance" do
      control = stale_control!

      migration.up

      expect(control.reload.source_vocabulary).to eq("aws_security_hub")
      expect(control.source_control_id).to eq("IAM.7")
    end

    # #1103's own scoping trap: a CDEF uploaded through the UI has no
    # import_metadata.source_type = "aws_labs", so selecting by document source
    # would skip exactly the case that was reported.
    it "re-enriches an uploaded CDEF, not only AWS Labs-sourced ones" do
      control = stale_control!
      expect(document.import_metadata["source_type"]).to be_nil

      migration.up

      expect(control.reload.control_id).not_to eq("ac-2_smt.j")
    end

    it "does not touch controls from another vocabulary" do
      other = document.cdef_controls.create!(
        title: "t", control_id: "ac-2_smt.j", control_family: "AC",
        source_control_id: "SV-12345", source_vocabulary: "disa_stig"
      )

      migration.up

      expect(other.reload.control_id).to eq("ac-2_smt.j")
    end
  end

  # [[feedback_data_migration_idempotency]] — running twice must converge, and a
  # run that died partway must be completable by running again.
  describe "idempotency and resume" do
    it "produces the same result when run twice" do
      control = stale_control!

      migration.up
      first_id     = control.reload.control_id
      first_fields = control.cdef_control_fields.count
      first_rows   = aws_config_converter.converter_entries.where(category: "mitre_vendored").count

      migration.up

      control.reload
      expect(control.control_id).to eq(first_id)
      expect(control.cdef_control_fields.count).to eq(first_fields)
      expect(aws_config_converter.converter_entries.where(category: "mitre_vendored").count)
        .to eq(first_rows)
    end

    it "completes documents left behind when an earlier run died partway" do
      finished = stale_control!
      other_doc = create(:cdef_document, file_type: "json")
      unfinished = other_doc.cdef_controls.create!(
        title: "t", control_id: "ac-2_smt.j", control_family: "AC",
        source_control_id: "IAM.7", source_vocabulary: "aws_security_hub"
      )

      # Simulate the first run dying after the first document.
      call_count = 0
      allow_any_instance_of(CdefNistEnrichmentService).to receive(:enrich!).and_wrap_original do |original, doc|
        call_count += 1
        raise ActiveRecord::StatementInvalid, "connection lost" if call_count == 2
        original.call(doc)
      end

      migration.up
      expect(finished.reload.control_id).not_to eq("ac-2_smt.j")

      # Second run, no failure injected this time.
      allow_any_instance_of(CdefNistEnrichmentService).to receive(:enrich!).and_call_original
      migration.up

      expect(unfinished.reload.control_id).not_to eq("ac-2_smt.j")
    end

    # A document that fails must be visible, not silently skipped (#968).
    it "records a degradation instead of stranding the whole run" do
      stale_control!
      allow_any_instance_of(CdefNistEnrichmentService)
        .to receive(:enrich!).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { migration.up }.not_to raise_error
      expect(document.reload).to be_nist_enrichment_degraded
    end
  end

  describe "#down" do
    it "is deliberately empty rather than restoring rev4 ids" do
      expect { migration.down }.not_to raise_error
    end
  end
end
