# frozen_string_literal: true

require "rails_helper"

# #1354, #1384 — the FedRAMP sample package and the real marketplace records
# the validator is checked against.
#
#   samples/fedramp-package-demo/            one valid document per FedRAMP
#                                            package schema, for one fictional
#                                            provider (manifest.json)
#   samples/fedramp-package-demo/invalid/    each broken one documented way
#                                            (invalid/manifest.json)
#   spec/fixtures/files/fedramp/marketplace/ real FedRAMP Marketplace package
#                                            overviews (PROVENANCE.json)
#
# Every expectation comes from a manifest written beside the files, so a
# sample that stops matching its manifest fails here, by name.
RSpec.describe "FedRAMP sample package (samples/fedramp-package-demo)" do
  root = Rails.root.join("samples/fedramp-package-demo")
  manifest = JSON.parse(root.join("manifest.json").read)
  invalid_manifest = JSON.parse(root.join("invalid/manifest.json").read)
  marketplace = Rails.root.join("spec/fixtures/files/fedramp/marketplace")
  provenance = JSON.parse(marketplace.join("PROVENANCE.json").read)

  def validate(path) = DocumentValidationService.call(File.read(path), filename: File.basename(path))

  def receive(boundary, path)
    ReceivedDocumentService.call(boundary: boundary, bytes: File.binread(path), source: "upload",
                                 filename: File.basename(path), content_type: "application/json")
  end

  def strip_why(warnings) = warnings.map { |w| w.slice("pointer", "message").symbolize_keys }

  describe "the manifests" do
    it "list every file in the directory, and one document per FedRAMP document schema" do
      listed = manifest["documents"].map { |d| d["file"] }
      on_disk = Dir[root.join("*.json")].map { |p| File.basename(p) } - [ "manifest.json" ]
      expect(listed).to match_array(on_disk)
      expect(manifest["documents"].map { |d| d["document_type"] }).to match_array(FedrampPackageSchemas.document_types)

      invalid_listed = invalid_manifest["documents"].map { |d| d["file"] }
      invalid_on_disk = Dir[root.join("invalid/*.json")].map { |p| File.basename(p) } - [ "manifest.json" ]
      expect(invalid_listed).to match_array(invalid_on_disk)
    end
  end

  describe "the valid package" do
    manifest["documents"].each do |entry|
      context entry["file"] do
        let(:path) { root.join(entry["file"]) }
        let(:data) { JSON.parse(File.read(path)) }

        it "names its vendored schema in $schema, and validates with zero errors and only the listed warnings" do
          expect(data["$schema"]).to eq(FedrampPackageSchemas.fetch(entry["document_type"]).id)

          result = validate(path)

          expect(result.errors).to eq([])
          expect(result).to be_valid
          expect(result.document_type).to eq(entry["document_type"])
          expect(result.warnings).to match_array(strip_why(entry.dig("expected", "warnings")))
          expect(result.warnings_total).to eq(entry.dig("expected", "warnings").size)
        end
      end
    end

    it "is one provider's package: every report points at the overview, which carries the FedRAMP ID" do
      provider = manifest["provider"]
      cpo = JSON.parse(root.join("certification-package-overview.json").read)
      expect(cpo.dig("serviceIdentification", "fedRampPackageId")).to eq(provider["fedRampPackageId"])
      expect(provider["fedRampPackageId"]).to match(ExchangeConnection::FEDRAMP_ID)
      expect(cpo.dig("serviceIdentification", "providerName")).to eq(provider["providerName"])

      reports = manifest["documents"].map { |d| JSON.parse(root.join(d["file"]).read) }
                                     .select { |d| d.key?("certificationPackageOverviewUri") }
      # Every document schema but the overview itself and the two marketplace
      # listings (assessor, advisor) points at the overview.
      expect(reports.size).to eq(FedrampPackageSchemas.document_types.size - 3)
      expect(reports.map { |d| d["certificationPackageOverviewUri"] }.uniq).to eq([ provider["certificationPackageOverviewUri"] ])
      expect(provider["certificationPackageOverviewUri"]).to start_with(cpo.dig("serviceProperties", "trustCenter", "url"))
    end

    it "names an assessor and an advisor whose own documents are in the package" do
      cpo = JSON.parse(root.join("certification-package-overview.json").read)
      assessor = JSON.parse(root.join("assessor-information.json").read)
      advisor = JSON.parse(root.join("advisor-information.json").read)

      expect(cpo.dig("assessor", "name")).to eq(assessor["assessorName"])
      expect(cpo["advisors"].map { |a| a["name"] }).to eq([ advisor["advisorName"] ])
    end

    it "uses Key Security Indicators and FedRAMP rules that exist in the vendored rules" do
      rules = JSON.parse(Rails.root.join("lib/data/fedramp/fedramp-consolidated-rules.json").read)
      ksis = rules["KSI"].values.flat_map { |family| family["indicators"].keys }
      sdr = JSON.parse(root.join("security-decision-record.json").read)

      expect(ksis).to include(*sdr["keySecurityIndicators"].map { |k| k["ksiId"] })
      ksi_ids = sdr["keySecurityIndicators"].map { |k| k["ksiId"] }
      expect(ksi_ids).not_to be_empty
      # FRR rule ids are keys of the rules' nested FRR tree.
      frr_ids = []
      collect = lambda do |node|
        next node.each { |item| collect.call(item) } if node.is_a?(Array)
        next unless node.is_a?(Hash)

        node.each do |key, value|
          frr_ids << key if key.match?(/\A[A-Z]{3}-[A-Z]{3}-[A-Z]{3}\z/)
          collect.call(value)
        end
      end
      collect.call(rules["FRR"])
      expect(frr_ids).to include(*sdr["fedRampRequirements"].map { |r| r["frrID"] })
    end

    it "uses only reserved example domains and fictional phone numbers" do
      text = Dir[root.join("**/*.json")].map { |p| File.read(p) }.join("\n")
      hosts = text.scan(%r{https?://([^/"\s]+)}).flatten.uniq - [ "fedramp.gov" ]
      expect(hosts).to all(match(/(\A|\.)example\.(com|org|net)\z/))
      emails = text.scan(/[\w.+-]+@([\w.-]+)/).flatten.uniq
      expect(emails).to all(match(/(\A|\.)example\.(com|org|net)\z/))
      expect(text.scan(/\b\d{3}[-.)]\s?\d{3}[-.]\d{4}\b/)).to all(match(/555[-.]01\d\d/))
    end
  end

  describe "the invalid variants" do
    invalid_manifest["documents"].each do |entry|
      context entry["file"] do
        it "fails with exactly the documented error" do
          result = validate(root.join("invalid", entry["file"]))

          expect(result).not_to be_valid
          expect(result.errors).to eq(entry["expected_errors"].map(&:symbolize_keys))
        end
      end
    end
  end

  describe "received into a boundary" do
    let(:boundary) { create(:authorization_boundary) }

    it "stores every valid document for review, each in its own stream" do
      outcomes = manifest["documents"].map { |entry| receive(boundary, root.join(entry["file"])) }

      expect(outcomes).to all(be_stored)
      docs = outcomes.map(&:document)
      expect(docs.map(&:state).uniq).to eq([ "pending_review" ])
      expect(docs.map(&:valid_document).uniq).to eq([ true ])
      expect(docs.map(&:document_type)).to eq(manifest["documents"].map { |d| d["document_type"] })
      expect(docs.map(&:stream_key).uniq.size).to eq(docs.size)
      expect(docs.find { |d| d.document_type == "certification-package-overview" }.fedramp_id)
        .to eq(manifest.dig("provider", "fedRampPackageId"))
    end

    it "stores every invalid variant as invalid, with its documented error" do
      invalid_manifest["documents"].each do |entry|
        outcome = receive(boundary, root.join("invalid", entry["file"]))

        expect(outcome).to be_stored, entry["file"]
        expect(outcome.document.state).to eq("invalid"), entry["file"]
        expect(outcome.document.validation_errors).to eq(entry["expected_errors"]), entry["file"]
      end
    end
  end

  describe "real FedRAMP Marketplace records (spec/fixtures/files/fedramp/marketplace)" do
    it "has a provenance entry, with a matching SHA-256, for every fixture" do
      on_disk = Dir[marketplace.join("*.json")].map { |p| File.basename(p) } - [ "PROVENANCE.json" ]
      expect(provenance["files"].keys).to match_array(on_disk)
      provenance["files"].each do |name, entry|
        expect(Digest::SHA256.file(marketplace.join(name)).hexdigest).to eq(entry["sha256"]), name
      end
    end

    provenance["files"].each do |name, entry|
      it "#{name} validates as its provenance records (valid: #{entry.dig('expected', 'valid')})" do
        result = validate(marketplace.join(name))
        expected = entry["expected"]

        expect(result.valid?).to eq(expected["valid"])
        expect(result.document_type).to eq(expected["document_type"])
        expect(result.errors).to eq(expected["errors"].map(&:symbolize_keys))
        expect(result.warnings_total).to eq(expected["warnings_total"])
      end
    end

    it "keeps no real person's contact details: every substituted value is a placeholder" do
      provenance["files"].each do |name, entry|
        data = JSON.parse(marketplace.join(name).read)
        entry["privacy_substitutions"].each do |sub|
          tokens = sub["pointer"].split("/").drop(1).map { |t| t.match?(/\A\d+\z/) ? t.to_i : t }
          expect(data.dig(*tokens)).to eq(sub["replacement"]), "#{name} #{sub['pointer']}"
        end
        contacts = Array(data["contactInformation"])
        expect(contacts.filter_map { |c| c["contactEmail"].presence }).to all(end_with("@example.com")), name
      end
    end
  end
end
