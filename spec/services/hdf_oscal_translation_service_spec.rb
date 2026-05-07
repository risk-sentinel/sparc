require "rails_helper"

RSpec.describe HdfOscalTranslationService do
  let(:runner) { instance_double(HdfRunner) }
  let(:service) { described_class.new(runner: runner) }

  describe "#hdf_to_oscal_sar" do
    it "shells `hdf convert --from hdf --to oscal-sar`" do
      expect(runner).to receive(:convert).with("/tmp/scan.hdf.json", from: "hdf", to: "oscal-sar")
                                           .and_return("assessment-results" => { "uuid" => "abc" })
      result = service.hdf_to_oscal_sar("/tmp/scan.hdf.json")
      expect(result.dig("assessment-results", "uuid")).to eq("abc")
    end

    context "with a boundary supplying back-matter enrichment (#449 L4)" do
      let(:boundary) { create(:authorization_boundary) }
      let(:evidence) do
        create(:evidence,
               authorization_boundary: boundary,
               title: "SOC 2 Type II Report",
               description: "Vendor's SOC 2 attestation",
               source: "vendor-supplied",
               evidence_type: "artifact",
               status: "attested",
               original_filename: "soc2.pdf",
               file_content_type: "application/pdf")
      end

      before do
        evidence.evidence_control_links.create!(control_id: "CA-2")
        create(:attestation, evidence: evidence, attester_name: "Auditor X",
               role: "assessor", status: "passed",
               attested_at: Time.utc(2026, 4, 1, 12, 0, 0))
      end

      it "merges Evidence records into back-matter.resources" do
        oscal_in = { "assessment-results" => { "uuid" => "abc" } }
        allow(runner).to receive(:convert).and_return(oscal_in)

        result = service.hdf_to_oscal_sar("/tmp/scan.hdf.json", boundary: boundary)
        resources = result.dig("assessment-results", "back-matter", "resources")
        expect(resources.length).to eq(1)
        expect(resources.first["uuid"]).to eq(evidence.uuid)
        expect(resources.first["title"]).to eq("SOC 2 Type II Report")
      end

      it "captures attestation, control, and source as props" do
        allow(runner).to receive(:convert).and_return("assessment-results" => {})
        result = service.hdf_to_oscal_sar("/tmp/scan.hdf.json", boundary: boundary)
        props = result.dig("assessment-results", "back-matter", "resources", 0, "props")
        names = props.map { |p| p["name"] }
        expect(names).to include("source", "evidence-type", "status", "control-id", "attestation")
      end

      it "emits an rlink referencing the evidence path" do
        allow(runner).to receive(:convert).and_return("assessment-results" => {})
        result = service.hdf_to_oscal_sar("/tmp/scan.hdf.json", boundary: boundary)
        rlinks = result.dig("assessment-results", "back-matter", "resources", 0, "rlinks")
        expect(rlinks.first["href"]).to match(%r{/evidences/})
        expect(rlinks.first["media-type"]).to eq("application/pdf")
      end
    end

    it "leaves back-matter untouched when no boundary is given" do
      oscal_in = { "assessment-results" => { "uuid" => "abc" } }
      allow(runner).to receive(:convert).and_return(oscal_in)
      result = service.hdf_to_oscal_sar("/tmp/scan.hdf.json")
      expect(result.dig("assessment-results", "back-matter")).to be_nil
    end
  end

  describe "#hdf_to_oscal_poam" do
    it "shells `hdf convert --from hdf --to oscal-poam`" do
      expect(runner).to receive(:convert).with("/tmp/scan.hdf.json", from: "hdf", to: "oscal-poam")
                                           .and_return("plan-of-action-and-milestones" => { "uuid" => "def" })
      result = service.hdf_to_oscal_poam("/tmp/scan.hdf.json")
      expect(result.dig("plan-of-action-and-milestones", "uuid")).to eq("def")
    end
  end

  describe "#oscal_poam_to_hdf_amendments" do
    it "shells `hdf convert --from oscal-poam` and verifies the result" do
      amendments = { "overrides" => [ { "type" => "poam", "controlId" => "AC-2" } ] }
      expect(runner).to receive(:convert).with("/tmp/poam.json", from: "oscal-poam")
                                           .and_return(amendments)
      expect(runner).to receive(:amend_verify).with(a_string_matching(%r{/hdf-amendments-.*\.json}))

      result = service.oscal_poam_to_hdf_amendments("/tmp/poam.json")
      expect(result).to eq(amendments)
    end

    it "propagates HdfRunner::Error if amend_verify fails" do
      amendments = { "overrides" => [ { "type" => "invalid" } ] }
      allow(runner).to receive(:convert).and_return(amendments)
      allow(runner).to receive(:amend_verify).and_raise(
        HdfRunner::Error.new("schema mismatch", command: "hdf amend verify ...", exit_code: 1, stderr: "")
      )
      expect {
        service.oscal_poam_to_hdf_amendments("/tmp/poam.json")
      }.to raise_error(HdfRunner::Error, /schema mismatch/)
    end
  end
end
