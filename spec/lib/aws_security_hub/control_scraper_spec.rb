# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/aws_security_hub/control_scraper")

RSpec.describe AwsSecurityHub::ControlScraper do
  let(:iam_fixture_path) do
    Rails.root.join("spec/fixtures/files/aws_security_hub/iam_controls.fixture.html")
  end

  let(:iam_html) { File.read(iam_fixture_path) }

  describe ".discover_service_pages" do
    it "extracts unique service-page slugs from anchor tags" do
      html = <<~HTML
        <html><body>
          <a href="./iam-controls.html#iam-3">IAM.3</a>
          <a href="./iam-controls.html#iam-7">IAM.7</a>
          <a href="./s3-controls.html#s3-5">S3.5</a>
          <a href="./does-not-match.html">other</a>
          <a href="/external/iam-controls.html">absolute</a>
        </body></html>
      HTML

      slugs = described_class.discover_service_pages(html)
      expect(slugs).to eq([ "iam-controls", "s3-controls" ])
    end

    it "returns empty array when no anchors match the controls pattern" do
      expect(described_class.discover_service_pages("<html></html>")).to eq([])
    end
  end

  describe ".parse_service_page (IAM fixture)" do
    let(:entries) { described_class.parse_service_page(iam_html, service_slug: "iam-controls") }

    it "extracts at least one [IAM.N]-prefixed entry" do
      expect(entries).not_to be_empty
      expect(entries.map { |e| e["sec_hub_id"] }).to all(start_with("IAM."))
    end

    it "captures sec_hub_id, title, and service_slug per entry" do
      sample = entries.first
      expect(sample["sec_hub_id"]).to match(/\AIAM\.\d+\z/)
      expect(sample["title"]).to be_a(String).and(satisfy { |t| !t.empty? })
      expect(sample["service_slug"]).to eq("iam-controls")
    end

    it "parses NIST.800-53.r5 mappings and produces OSCAL ids" do
      iam_3 = entries.find { |e| e["sec_hub_id"] == "IAM.3" }
      expect(iam_3).not_to be_nil
      expect(iam_3["nist_rev5_raw"]).to include("AC-2(1)", "AC-2(3)", "AC-3(15)")
      expect(iam_3["nist_oscal_ids"]).to include("ac-2.1", "ac-2.3", "ac-3.15")
    end

    it "captures the AWS Config rule name when present" do
      iam_3 = entries.find { |e| e["sec_hub_id"] == "IAM.3" }
      expect(iam_3["aws_config_rule"]).to eq("access-keys-rotated")
    end

    it "captures severity and category" do
      iam_3 = entries.find { |e| e["sec_hub_id"] == "IAM.3" }
      expect(iam_3["severity"]).to eq("Medium")
      expect(iam_3["category"]).to match(/Protect/)
    end

    it "preserves the raw related-requirements string for audit" do
      iam_3 = entries.find { |e| e["sec_hub_id"] == "IAM.3" }
      expect(iam_3["related_requirements_raw"]).to include("NIST.800-53.r5")
    end
  end

  describe ".parse_service_page (synthetic check-based control)" do
    it "leaves aws_config_rule nil when the section has no Config rule field" do
      html = <<~HTML
        <html><body>
        <h2 id="cloudtrail-1">[CloudTrail.1] Check-based control with no Config rule</h2>
        <p><b>Related requirements:</b> NIST.800-53.r5 AU-2</p>
        <p><b>Severity:</b> Medium</p>
        </body></html>
      HTML

      entries = described_class.parse_service_page(html, service_slug: "cloudtrail-controls")
      expect(entries.length).to eq(1)
      expect(entries.first["sec_hub_id"]).to eq("CloudTrail.1")
      expect(entries.first["aws_config_rule"]).to be_nil
      expect(entries.first["nist_oscal_ids"]).to eq([ "au-2" ])
    end
  end

  describe ".parse_service_page (skip non-control h2s)" do
    it "ignores h2 headings that aren't bracketed control titles" do
      html = <<~HTML
        <html><body>
        <h2 id="overview">Overview of IAM controls</h2>
        <p>Some intro text.</p>
        <h2 id="iam-1">[IAM.1] Description</h2>
        <p><b>Related requirements:</b> NIST.800-53.r5 IA-5</p>
        </body></html>
      HTML

      entries = described_class.parse_service_page(html, service_slug: "iam-controls")
      expect(entries.length).to eq(1)
      expect(entries.first["sec_hub_id"]).to eq("IAM.1")
    end
  end

  describe ".build_document" do
    it "wraps entries in SPARC envelope with attribution and rev=5" do
      entries = [ { "sec_hub_id" => "IAM.3", "title" => "x" } ]
      doc = described_class.build_document(entries, scraped_at: Time.utc(2026, 5, 19))

      expect(doc["format"]).to eq("aws_security_hub_to_nist")
      expect(doc["version"]).to eq("scraped-2026-05-19")
      expect(doc["rev"]).to eq(5)
      expect(doc["total_entries"]).to eq(1)
      expect(doc["source"]).to include("docs.aws.amazon.com")
      expect(doc["attribution"]).to match(/Amazon/i)
    end

    it "sorts mappings by sec_hub_id" do
      entries = [
        { "sec_hub_id" => "IAM.10" },
        { "sec_hub_id" => "IAM.1" },
        { "sec_hub_id" => "IAM.5" }
      ]
      doc = described_class.build_document(entries)
      ids = doc["mappings"].map { |m| m["sec_hub_id"] }
      # String sort, not numeric: "IAM.1" < "IAM.10" < "IAM.5".
      expect(ids).to eq([ "IAM.1", "IAM.10", "IAM.5" ])
    end
  end
end
