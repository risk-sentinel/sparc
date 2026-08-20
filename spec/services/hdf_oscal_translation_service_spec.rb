require "rails_helper"

RSpec.describe HdfOscalTranslationService do
  let(:runner) { instance_double(HdfRunner) }
  let(:service) { described_class.new(runner: runner) }

  # #831 — hdf_to_oscal_sar now validates its output against the OSCAL schema
  # before returning, so these stubs must be documents the schema accepts.
  # A `{"assessment-results" => {"uuid" => "abc"}}` placeholder is exactly the
  # kind of thing the gate exists to stop, and using one here would have made
  # these examples pass against output no OSCAL tool would take.
  def minimal_sar(uuid: "11111111-1111-4111-8111-111111111111")
    {
      "assessment-results" => {
        "uuid" => uuid,
        "metadata" => {
          "title" => "Stub Assessment Results",
          "last-modified" => "2026-07-27T00:00:00Z",
          "version" => "1.0",
          "oscal-version" => "1.1.2"
        },
        "import-ap" => { "href" => "#22222222-2222-4222-8222-222222222222" },
        "results" => [ {
          "uuid" => "33333333-3333-4333-8333-333333333333",
          "title" => "Stub Result",
          "description" => "Stub result description.",
          "start" => "2026-07-27T00:00:00Z",
          "reviewed-controls" => { "control-selections" => [ { "include-all" => {} } ] }
        } ]
      }
    }
  end

  # #1017 — the same reasoning as `minimal_sar`, for the two POA&M paths. The
  # placeholder these examples used to stub — `{"plan-of-action-and-milestones"
  # => {"uuid" => "def"}}` — is precisely what the gate exists to stop, and it
  # is why the gap went unnoticed: the spec passed against a document no OSCAL
  # tool would accept, because nothing validated it.
  def minimal_poam(uuid: "11111111-1111-4111-8111-111111111111")
    {
      "plan-of-action-and-milestones" => {
        "uuid" => uuid,
        "metadata" => {
          "title" => "Stub POA&M",
          "last-modified" => "2026-07-27T00:00:00Z",
          "version" => "1.0",
          "oscal-version" => "1.1.2"
        },
        "import-ssp" => { "href" => "#22222222-2222-4222-8222-222222222222" },
        "poam-items" => [ {
          "uuid" => "33333333-3333-4333-8333-333333333333",
          "title" => "Stub item",
          "description" => "Stub description."
        } ]
      }
    }
  end

  describe "#hdf_to_oscal_sar" do
    it "shells `hdf convert --from hdf --to oscal-sar`" do
      expect(runner).to receive(:convert).with("/tmp/scan.hdf.json", from: "hdf", to: "oscal-sar")
                                           .and_return(minimal_sar(uuid: "44444444-4444-4444-8444-444444444444"))
      result = service.hdf_to_oscal_sar("/tmp/scan.hdf.json")
      expect(result.dig("assessment-results", "uuid")).to eq("44444444-4444-4444-8444-444444444444")
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
        allow(runner).to receive(:convert).and_return(minimal_sar)

        result = service.hdf_to_oscal_sar("/tmp/scan.hdf.json", boundary: boundary)
        resources = result.dig("assessment-results", "back-matter", "resources")
        expect(resources.length).to eq(1)
        expect(resources.first["uuid"]).to eq(evidence.uuid)
        expect(resources.first["title"]).to eq("SOC 2 Type II Report")
      end

      it "captures attestation, control, and source as props" do
        allow(runner).to receive(:convert).and_return(minimal_sar)
        result = service.hdf_to_oscal_sar("/tmp/scan.hdf.json", boundary: boundary)
        props = result.dig("assessment-results", "back-matter", "resources", 0, "props")
        names = props.map { |p| p["name"] }
        expect(names).to include("source", "evidence-type", "status", "control-id", "attestation")
      end

      it "emits an rlink referencing the durable artifact resolver (#680)" do
        allow(runner).to receive(:convert).and_return(minimal_sar)
        result = service.hdf_to_oscal_sar("/tmp/scan.hdf.json", boundary: boundary)
        rlinks = result.dig("assessment-results", "back-matter", "resources", 0, "rlinks")
        expect(rlinks.first["href"]).to match(%r{/artifacts/[0-9a-f-]{36}\z})
        expect(rlinks.first["media-type"]).to eq("application/pdf")
      end
    end

    it "leaves back-matter untouched when no boundary is given" do
      allow(runner).to receive(:convert).and_return(minimal_sar)
      result = service.hdf_to_oscal_sar("/tmp/scan.hdf.json")
      expect(result.dig("assessment-results", "back-matter")).to be_nil
    end
  end

  describe "#hdf_to_oscal_poam" do
    it "shells `hdf convert --from hdf --to oscal-poam`" do
      expect(runner).to receive(:convert).with("/tmp/scan.hdf.json", from: "hdf", to: "oscal-poam")
                                           .and_return(minimal_poam(uuid: "44444444-4444-4444-8444-444444444444"))
      result = service.hdf_to_oscal_poam("/tmp/scan.hdf.json")
      expect(result.dig("plan-of-action-and-milestones", "uuid"))
        .to eq("44444444-4444-4444-8444-444444444444")
    end

    it "refuses to return a POA&M that fails the OSCAL schema (#1017)" do
      allow(runner).to receive(:convert)
        .and_return("plan-of-action-and-milestones" => { "uuid" => "def" })

      expect { service.hdf_to_oscal_poam("/tmp/scan.hdf.json") }
        .to raise_error(OscalValidationError)
    end
  end

  # #1017 — the reachable half of the gap. `poam_from_hdf` 501s by design since
  # hdf-cli 3.2.0, so this is the path a tenant CI pipeline actually calls, and
  # it was emitting `poam-items: null` with a 200.
  describe "#oscal_poam_from_hdf_amendments" do
    it "shells `hdf convert --from hdf-amendments --to oscal-poam`" do
      expect(runner).to receive(:convert)
        .with("/tmp/amendments.json", from: "hdf-amendments", to: "oscal-poam")
        .and_return(minimal_poam(uuid: "55555555-5555-4555-8555-555555555555"))

      result = service.oscal_poam_from_hdf_amendments("/tmp/amendments.json")
      expect(result.dig("plan-of-action-and-milestones", "uuid"))
        .to eq("55555555-5555-4555-8555-555555555555")
    end

    it "refuses a POA&M whose poam-items is null, which is what the gap emitted" do
      allow(runner).to receive(:convert).and_return(
        "plan-of-action-and-milestones" => {
          "uuid" => "66666666-6666-4666-8666-666666666666",
          "metadata" => { "title" => "", "last-modified" => "2026-08-20T23:29:17Z",
                          "version" => "1.0.0", "oscal-version" => "1.1.2" },
          "import-ssp" => { "href" => "#" },
          "poam-items" => nil
        }
      )

      expect { service.oscal_poam_from_hdf_amendments("/tmp/amendments.json") }
        .to raise_error(OscalValidationError, /poam-items/)
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
