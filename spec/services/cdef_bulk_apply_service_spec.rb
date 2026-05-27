# frozen_string_literal: true

require "rails_helper"

# #499 slice 3 — preview path. Slice 4 will add the confirm/apply
# coverage; this spec covers the read-only preview + token round-trip.
RSpec.describe CdefBulkApplyService do
  let(:cdef) { create(:cdef_document, name: "Bulk Apply Target", cdef_type: "custom") }
  let(:converter) do
    Converter.create!(name: "Test Converter #{SecureRandom.hex(4)}",
                      converter_type: "custom", status: "complete",
                      metadata_extra: { "target_rev" => "5" })
  end

  before do
    [
      [ "src-1", "ac-2" ],
      [ "src-2", "ac-3" ],
      [ "src-3", "sc-7" ]
    ].each_with_index do |(src, tgt), idx|
      ConverterEntry.create!(converter: converter, source_id: src, target_id: tgt,
                             relationship: "equivalent", row_order: idx)
    end
  end

  describe "#preview" do
    it "returns one row per converter entry with status: ready when CDEF is empty" do
      result = described_class.new(cdef: cdef, converter: converter).preview
      expect(result.rows.length).to eq(3)
      expect(result.rows.map(&:status).uniq).to eq([ "ready" ])
      expect(result.stats[:ready]).to eq(3)
      expect(result.stats[:already_present]).to eq(0)
    end

    it "flags already-present targets so they're not re-added" do
      cdef.cdef_controls.create!(control_id: "ac-2", title: "Account Management")
      result = described_class.new(cdef: cdef, converter: converter).preview
      ac2_row = result.rows.find { |r| r.target_id == "ac-2" }
      expect(ac2_row.status).to eq("already_present")
      expect(result.stats[:already_present]).to eq(1)
      expect(result.stats[:ready]).to eq(2)
    end

    it "filters to source_ids when provided" do
      result = described_class.new(cdef: cdef, converter: converter,
                                   source_ids: [ "src-1" ]).preview
      expect(result.rows.length).to eq(1)
      expect(result.rows.first.source_id).to eq("src-1")
    end

    it "refuses to preview against an AWS-Labs-sourced CDEF" do
      cdef.update!(import_metadata: { "source_type" => "aws_labs", "source_url" => "https://example/cdef.json" })
      expect {
        described_class.new(cdef: cdef, converter: converter).preview
      }.to raise_error(ArgumentError, /clone first/)
    end

    it "returns a token that round-trips via decode_token!" do
      result  = described_class.new(cdef: cdef, converter: converter).preview
      payload = described_class.decode_token!(result.token)
      expect(payload["cdef_uuid"]).to eq(cdef.uuid)
      expect(payload["converter_uuid"]).to eq(converter.uuid)
      expect(payload["rows"].length).to eq(3)
    end

    it "rejects a tampered token" do
      result = described_class.new(cdef: cdef, converter: converter).preview
      tampered = result.token.sub(/\.\w/, ".X")
      expect {
        described_class.decode_token!(tampered)
      }.to raise_error(ArgumentError, /signature invalid/)
    end

    it "rejects an expired token" do
      result = described_class.new(cdef: cdef, converter: converter).preview
      Timecop.travel(Time.current + (CdefBulkApplyService::TOKEN_TTL + 1.minute)) do
        expect {
          described_class.decode_token!(result.token)
        }.to raise_error(ArgumentError, /expired/)
      end
    rescue NameError
      # Timecop not present — fall back to direct payload mutation
      raw_payload = Base64.urlsafe_decode64(result.token.split(".").first)
      mutated     = JSON.parse(raw_payload).merge("issued_at" => 1.hour.ago.to_i)
      mutated_enc = Base64.urlsafe_encode64(JSON.generate(mutated), padding: false)
      mutated_sig = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"),
                                            CdefBulkApplyService.signing_key, mutated_enc)
      expect {
        described_class.decode_token!("#{mutated_enc}.#{mutated_sig}")
      }.to raise_error(ArgumentError, /expired/)
    end
  end

  describe ".apply! (slice 4)" do
    it "adds new CdefControl rows for each ready row in the token" do
      token = described_class.new(cdef: cdef, converter: converter).preview.token

      expect {
        described_class.apply!(cdef: cdef, token: token)
      }.to change { cdef.cdef_controls.count }.by(3)

      added = cdef.cdef_controls.pluck(:control_id)
      expect(added).to contain_exactly("ac-2", "ac-3", "sc-7")
    end

    it "is idempotent on re-apply (already_present rows skipped)" do
      token = described_class.new(cdef: cdef, converter: converter).preview.token
      described_class.apply!(cdef: cdef, token: token)

      # Re-preview + re-apply produces no new rows.
      token2 = described_class.new(cdef: cdef, converter: converter).preview.token
      expect {
        described_class.apply!(cdef: cdef, token: token2)
      }.not_to change { cdef.cdef_controls.count }
    end

    it "emits a cdef_bulk_apply_converter_applied audit event" do
      token = described_class.new(cdef: cdef, converter: converter).preview.token

      expect {
        described_class.apply!(cdef: cdef, token: token)
      }.to change { AuditEvent.where(action: "cdef_bulk_apply_converter_applied").count }.by(1)

      event = AuditEvent.where(action: "cdef_bulk_apply_converter_applied").last
      expect(event.subject_id).to eq(cdef.id)
      expect(event.metadata["added_count"]).to eq(3)
    end

    it "rejects a token whose cdef_uuid doesn't match the supplied cdef" do
      token = described_class.new(cdef: cdef, converter: converter).preview.token
      other = create(:cdef_document, name: "Different CDEF")
      expect {
        described_class.apply!(cdef: other, token: token)
      }.to raise_error(ArgumentError, /CDEF mismatch/)
    end

    it "requires explicit selection for needs_disambiguation rows" do
      # Simulate 1→N: add a second target for src-1
      ConverterEntry.create!(converter: converter, source_id: "src-1", target_id: "ac-2.1",
                             relationship: "equivalent", row_order: 99)
      token = described_class.new(cdef: cdef, converter: converter).preview.token

      # Without selection: 1→N rows skipped (the other 2 ready rows still added)
      added = described_class.apply!(cdef: cdef, token: token)
      expect(added[:added_control_ids]).not_to include("ac-2", "ac-2.1")
      expect(added[:added_control_ids]).to contain_exactly("ac-3", "sc-7")
    end

    it "applies a needs_disambiguation row when caller passes selected_target_ids" do
      ConverterEntry.create!(converter: converter, source_id: "src-1", target_id: "ac-2.1",
                             relationship: "equivalent", row_order: 99)
      token = described_class.new(cdef: cdef, converter: converter).preview.token

      added = described_class.apply!(cdef: cdef, token: token,
                                     selected_target_ids: { "src-1" => "ac-2" })
      expect(added[:added_control_ids]).to include("ac-2")
      expect(added[:added_control_ids]).not_to include("ac-2.1")
    end
  end

  describe ".apply! back-matter provenance (slice 6)" do
    it "cites the converter as a BackMatterResource on first apply" do
      converter.update!(metadata_extra: converter.metadata_extra.merge(
        "source" => "https://csrc.nist.gov/example/converter.json"
      ))
      token = described_class.new(cdef: cdef, converter: converter).preview.token

      expect {
        described_class.apply!(cdef: cdef, token: token)
      }.to change {
        cdef.back_matter_resources.where("title LIKE ?", "Converter:%").count
      }.by(1)

      bmr = cdef.back_matter_resources.find_by("title LIKE ?", "Converter:%")
      expect(bmr.href).to eq("https://csrc.nist.gov/example/converter.json")
      expect(bmr.source).to eq("imported")
      expect(bmr.resource_data["converter_uuid"]).to eq(converter.uuid)
      expect(bmr.resource_data["target_rev"]).to eq("5")
    end

    it "is idempotent — re-applying the same converter does not duplicate the citation" do
      token = described_class.new(cdef: cdef, converter: converter).preview.token
      described_class.apply!(cdef: cdef, token: token)
      first_count = cdef.back_matter_resources.where("title LIKE ?", "Converter:%").count

      # Re-preview + re-apply (idempotent on already_present rows AND on citation)
      token2 = described_class.new(cdef: cdef, converter: converter).preview.token
      described_class.apply!(cdef: cdef, token: token2)
      expect(cdef.back_matter_resources.where("title LIKE ?", "Converter:%").count).to eq(first_count)
    end

    it "does NOT cite when nothing was added (e.g. all rows already_present)" do
      # First apply: adds everything + cites converter.
      token = described_class.new(cdef: cdef, converter: converter).preview.token
      described_class.apply!(cdef: cdef, token: token)

      # Wipe the citation but keep the controls — confirms cite path is
      # add-gated (nothing added → no citation churn).
      cdef.back_matter_resources.where("title LIKE ?", "Converter:%").destroy_all
      token2 = described_class.new(cdef: cdef, converter: converter).preview.token
      described_class.apply!(cdef: cdef, token: token2)
      expect(cdef.back_matter_resources.where("title LIKE ?", "Converter:%").count).to eq(0)
    end

    it "cites the rev mapping in addition to the converter when normalization is in play" do
      rev4_catalog = create(:control_catalog, name: "NIST SP 800-53 Rev 4")
      rev5_catalog = create(:control_catalog, name: "NIST SP 800-53 Rev 5")
      mapping = ControlMapping.create!(
        name: "NIST SP 800-53 Rev 4 → Rev 5",
        source_catalog: rev4_catalog, target_catalog: rev5_catalog,
        status: "complete", method_type: "automation",
        metadata_extra: { "source_xlsx" => "https://csrc.nist.gov/sp800-53r4-to-r5.xlsx" }
      )
      ControlMappingEntry.create!(control_mapping: mapping, source_control_id: "ac-2",
                                  target_control_id: "ac-2", relationship: "equivalent",
                                  source_type: "control", target_type: "control", row_order: 0)

      rev4_converter = Converter.create!(name: "Rev4 Cite Test", converter_type: "custom",
                                         status: "complete",
                                         metadata_extra: { "target_rev" => "4",
                                                           "source" => "https://example/r4.json" })
      ConverterEntry.create!(converter: rev4_converter, source_id: "src-x", target_id: "ac-2",
                             relationship: "equivalent", row_order: 0)

      token = described_class.new(cdef: cdef, converter: rev4_converter,
                                  target_rev: "5").preview.token
      described_class.apply!(cdef: cdef, token: token)

      titles = cdef.back_matter_resources.pluck(:title)
      expect(titles).to include(a_string_starting_with("Converter:"))
      expect(titles).to include(a_string_starting_with("Rev translation:"))
    end
  end

  describe "rev translation via ControlIdNormalizer" do
    let!(:rev4_catalog) { create(:control_catalog, name: "NIST SP 800-53 Rev 4") }
    let!(:rev5_catalog) { create(:control_catalog, name: "NIST SP 800-53 Rev 5") }
    let!(:mapping) do
      ControlMapping.create!(name: "NIST SP 800-53 Rev 4 → Rev 5",
                             source_catalog: rev4_catalog, target_catalog: rev5_catalog,
                             status: "complete", method_type: "automation")
    end
    let(:rev4_converter) do
      Converter.create!(name: "Rev4 Conv #{SecureRandom.hex(4)}", converter_type: "custom",
                        status: "complete", metadata_extra: { "target_rev" => "4" })
    end

    before do
      # Converter emits Rev 4 ids
      ConverterEntry.create!(converter: rev4_converter, source_id: "aws-rule-1",
                             target_id: "ac-2", relationship: "equivalent", row_order: 0)
      # Rev4 ac-2 → Rev5 ac-2 (1:1 equivalent)
      ControlMappingEntry.create!(control_mapping: mapping, source_control_id: "ac-2",
                                  target_control_id: "ac-2", relationship: "equivalent",
                                  source_type: "control", target_type: "control", row_order: 0)
    end

    it "translates targets when target_rev differs from converter native rev" do
      result = described_class.new(cdef: cdef, converter: rev4_converter, target_rev: "5").preview
      expect(result.rows.length).to eq(1)
      expect(result.rows.first.target_id).to eq("ac-2")
      expect(result.rows.first.relationship).to eq("equivalent")
    end

    it "no-translates when target_rev matches converter native rev" do
      result = described_class.new(cdef: cdef, converter: rev4_converter, target_rev: "4").preview
      expect(result.rows.length).to eq(1)
      expect(result.rows.first.target_id).to eq("ac-2")
    end
  end
end
