# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/aws_security_hub/composite_mapping_builder")

# Issue #491 — Smoke test that exercises the AWS Security Hub seed section
# end-to-end against the real vendored + scraped data files. We invoke the
# composite builder directly and then assert the row shape that
# db/seeds/converters.rb would insert.
RSpec.describe "AWS Security Hub converter seed", type: :model do
  let(:aws_path)   { Rails.root.join("lib/data_mappings/aws_security_hub_to_nist.json") }
  let(:mitre_path) { Rails.root.join("lib/data_mappings/mitre_aws_config_to_nist.json") }

  it "the required data files are present" do
    expect(File.exist?(aws_path)).to be(true), "Missing #{aws_path}"
    expect(File.exist?(mitre_path)).to be(true), "Missing #{mitre_path}"
  end

  it "composes rows that satisfy the converter_entries unique-pair invariant" do
    rows, _stats = AwsSecurityHub::CompositeMappingBuilder.from_paths(
      aws_direct_path: aws_path, mitre_path: mitre_path
    )

    pairs = rows.map { |r| [ r["source_id"], r["target_id"] ] }
    expect(pairs.length).to eq(pairs.uniq.length),
      "Composite emitted duplicate (source_id, target_id) pairs which would violate the unique index"
  end

  it "creates a Converter + ConverterEntry rows via the seed pipeline" do
    rows, _stats = AwsSecurityHub::CompositeMappingBuilder.from_paths(
      aws_direct_path: aws_path, mitre_path: mitre_path
    )

    converter = Converter.create!(
      name: "AWS Security Hub → NIST SP 800-53 rev5 (test)",
      converter_type: "aws_security_hub_to_nist",
      source_framework: "AWS Security Hub",
      target_framework: "NIST SP 800-53",
      version: "test",
      description: "spec",
      status: "complete"
    )

    row_order = 0
    entries = rows.first(50).map do |r|
      {
        converter_id: converter.id,
        source_id: r["source_id"],
        target_id: r["target_id"],
        relationship: r["relationship"],
        category: r["category"],
        remarks: r["remarks"],
        row_order: row_order += 1,
        uuid: SecureRandom.uuid,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    expect { ConverterEntry.insert_all(entries) }.to change(ConverterEntry, :count).by(entries.length)
    expect(converter.converter_entries.count).to eq(entries.length)
  end

  it "the categories distinguish aws_direct vs mitre_fallback for downstream queries" do
    rows, _stats = AwsSecurityHub::CompositeMappingBuilder.from_paths(
      aws_direct_path: aws_path, mitre_path: mitre_path
    )

    categories = rows.map { |r| r["category"] }.uniq.sort
    expect(categories).to eq([ "aws_direct", "mitre_fallback" ])
  end
end
