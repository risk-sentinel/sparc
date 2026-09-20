require "rails_helper"

# Issue #1103 — a CDEF uploaded through the UI got its controls, and none of
# their NIST mappings.
#
# `enrich_with_nist_mappings!` was private to AwsLabsCdefImportService, so it
# ran only on the weekly AWS Labs refresh. An upload went
# DocumentConversionJob -> CdefJsonParserService#parse and stopped: every AWS
# control kept the Security Hub identifier it arrived with (`IAM.3`), resolved
# to no NIST control and belonged to no NIST family. The controls existed, so
# the import looked clean — but the heat map, coverage and the Security Hub ->
# NIST converter all had nothing to work with. That is the reported defect.
#
# These examples pin the UPLOAD path specifically. The AWS Labs refresh path is
# already covered in spec/services/aws_labs_cdef_import_service_spec.rb, and
# both now run the same CdefNistEnrichmentService.
RSpec.describe DocumentConversionJob, type: :job do
  describe "CDEF NIST enrichment on the upload path (#1103)" do
    let(:fixture_path) do
      Rails.root.join("spec/fixtures/files/components/aws_labs/iam-cd-realistic.json")
    end

    let(:document) { create(:cdef_document, file_type: "json", status: "pending") }

    let(:sec_hub_converter) do
      create(:converter, converter_type: "aws_security_hub_to_nist",
                         source_framework: "AWS Security Hub", status: "complete")
    end

    let(:aws_config_converter) do
      create(:converter, converter_type: "aws_config_to_nist",
                         source_framework: "AWS Config", status: "complete")
    end

    def attach_fixture!(doc)
      doc.file.attach(
        io: File.open(fixture_path),
        filename: File.basename(fixture_path),
        content_type: "application/json"
      )
    end

    def fields_for(doc, sec_hub_id)
      control = doc.cdef_controls.find_by(source_control_id: sec_hub_id)
      return nil if control.nil?
      control.cdef_control_fields.pluck(:field_name, :field_value).to_h
    end

    before do
      # Hop 1 — IAM.3 resolves directly.
      [ "ac-2.1", "ac-3.15" ].each_with_index do |target, i|
        ConverterEntry.create!(
          converter: sec_hub_converter, source_id: "IAM.3", target_id: target,
          relationship: "intersects", category: "aws_direct", row_order: i + 1
        )
      end

      # Hop 2 — IAM.7 has no direct row; the bridge names its Config Rule and
      # the Config converter maps that rule.
      ConverterEntry.create!(
        converter: aws_config_converter, source_id: "iam-password-policy",
        target_id: "ia-5.1", relationship: "intersects",
        category: "mitre_vendored", row_order: 1
      )

      # IAM.99999 resolves nowhere, on either hop.
      bridge = { "IAM.3" => "access-keys-rotated", "IAM.7" => "iam-password-policy", "IAM.99999" => nil }
      allow_any_instance_of(CdefNistEnrichmentService)
        .to receive(:sec_hub_config_rule_bridge).and_return(bridge)

      attach_fixture!(document)
    end

    it "resolves a directly-mapped Security Hub control to its NIST ids" do
      described_class.new.perform(:cdef, document.id)

      expect(fields_for(document.reload, "IAM.3")).to include(
        "aws_security_hub_id" => "IAM.3",
        "nist_oscal_ids"      => "ac-2.1,ac-3.15",
        "nist_primary_id"     => "ac-2.1",
        "nist_mapping_source" => "aws_direct"
      )
    end

    it "chains through the AWS Config Rule when there is no direct mapping" do
      described_class.new.perform(:cdef, document.id)

      expect(fields_for(document.reload, "IAM.7")).to include(
        "nist_oscal_ids"      => "ia-5.1",
        "nist_mapping_source" => "via_config_rule",
        "aws_config_rule"     => "iam-password-policy"
      )
    end

    # The heart of the bug. `control_id` is the column every NIST-oriented view
    # groups by; before the fix it held "iam.3" — a Security Hub rule wearing a
    # NIST control's clothes — and `control_family` held "IAM", a family that
    # does not exist in 800-53.
    it "moves the NIST reference into control_id and the matching family" do
      described_class.new.perform(:cdef, document.id)

      iam3 = document.reload.cdef_controls.find_by(source_control_id: "IAM.3")
      expect(iam3.control_id).to eq("ac-2.1")
      expect(iam3.control_family).to eq("AC")
      expect(iam3.source_control_id).to eq("IAM.3")
      expect(iam3.source_vocabulary).to eq("aws_security_hub")
    end

    # Both directions. An unresolvable rule must end up with NO control id
    # rather than keeping its Security Hub id, or it lands on the heat map as
    # its own bogus family (#912).
    it "leaves an unresolvable control unmapped, and does not pass its Security Hub id off as NIST" do
      described_class.new.perform(:cdef, document.id)

      unmapped = document.reload.cdef_controls.find_by(source_control_id: "IAM.99999")
      expect(unmapped).to be_present
      expect(unmapped.control_id).to be_nil
      expect(unmapped.control_family).to be_nil
      expect(fields_for(document, "IAM.99999")).not_to include("nist_mapping_source")
    end

    it "still completes the document" do
      described_class.new.perform(:cdef, document.id)

      expect(document.reload.status).to eq("completed")
      expect(document).not_to be_nist_enrichment_degraded
    end

    # Re-running must converge, not duplicate: the enrichment fields are
    # upserted by name, so a second pass rewrites them in place.
    it "is idempotent across a re-run" do
      described_class.new.perform(:cdef, document.id)
      before_count = document.reload.cdef_controls
                             .find_by(source_control_id: "IAM.3").cdef_control_fields.count

      CdefNistEnrichmentService.new.enrich!(document.reload)

      after = document.reload.cdef_controls.find_by(source_control_id: "IAM.3")
      expect(after.cdef_control_fields.count).to eq(before_count)
      expect(after.control_id).to eq("ac-2.1")
    end

    context "when the Security Hub converter has not been seeded" do
      it "leaves the controls alone instead of failing the import" do
        # A fresh instance that has never run db:seed has no converters at all.
        ConverterEntry.where(converter: sec_hub_converter).delete_all
        sec_hub_converter.destroy!

        described_class.new.perform(:cdef, document.id)

        expect(document.reload.status).to eq("completed")
        expect(document.cdef_controls.count).to be_positive
      end
    end

    # #968's partial-success contract, applied to enrichment: a converter
    # failure must not destroy a document that parsed correctly, but it must
    # not pass for a clean import either.
    context "when enrichment raises" do
      before do
        allow_any_instance_of(CdefNistEnrichmentService)
          .to receive(:enrich!).and_raise(ActiveRecord::StatementInvalid, "converter exploded")
      end

      it "completes the document but records the degradation on it" do
        described_class.new.perform(:cdef, document.id)

        document.reload
        expect(document.status).to eq("completed")
        expect(document.cdef_controls.count).to be_positive
        expect(document).to be_nist_enrichment_degraded
        expect(document.import_metadata["nist_enrichment_error"]).to match(/converter exploded/)
      end
    end

    it "does not touch a non-CDEF document type" do
      profile = create(:profile_document, file_type: "json", status: "pending")
      profile.file.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/profiles/small-resolved-profile-catalog.json")),
        filename: "small-resolved-profile-catalog.json",
        content_type: "application/json"
      )

      expect_any_instance_of(CdefNistEnrichmentService).not_to receive(:enrich!)
      described_class.new.perform(:profile, profile.id)

      expect(profile.reload.status).to eq("completed")
    end
  end
end
