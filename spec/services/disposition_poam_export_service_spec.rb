# frozen_string_literal: true

require "rails_helper"

# #1368 — the dispositions as an OSCAL POA&M in NIST's vocabulary.
#
# hdf converts the amendments; this service completes each risk. Without an hdf
# binary (CI, #835) the converter is stubbed with a POA&M hdf-cli 3.8.0 really
# produced (spec/fixtures/files/hdf/oscal_poam_from_amendments_v3.8.0.json);
# the completed document still goes through SPARC's real OSCAL schema
# validation. With the binary, the whole path runs for real.
RSpec.describe DispositionPoamExportService do
  let(:boundary) { create(:authorization_boundary) }
  let(:scan_run) { create(:scan_run, authorization_boundary: boundary) }
  let(:hdf_poam) do
    JSON.parse(Rails.root.join("spec/fixtures/files/hdf/oscal_poam_from_amendments_v3.8.0.json").read)
        .except("_provenance")
  end
  let(:runner) do
    instance_double(HdfRunner, amend_verify: true).tap do |r|
      allow(r).to receive(:convert).and_return(hdf_poam)
    end
  end

  def dispositioned(control_id, *traits, kind:, **attrs)
    create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
           control_id: control_id, severity: "HIGH")
    create(:finding_disposition, *traits, authorization_boundary: boundary, control_id: control_id, kind: kind, **attrs)
  end

  def risk_for(doc, control_id)
    doc.dig("plan-of-action-and-milestones", "risks").find do |risk|
      risk["props"].any? { |p| p["name"] == "hdf-requirement-id" && p["value"] == control_id }
    end
  end

  context "with the converter's output" do
    let!(:vendor) do
      dispositioned("CVE-2026-0001", kind: "vendorDependency", reason: "awaiting the vendor's patch",
                    nist_risk_status: "open", nist_response_lifecycle: "planned", nist_facet_state: "initial",
                    nist_likelihood: "moderate", nist_impact: "high")
    end
    let!(:false_positive) do
      dispositioned("CVE-2026-0002", kind: "falsePositive", reason: "code path not reachable",
                    nist_risk_status: "deviation-approved", nist_response_lifecycle: "completed",
                    nist_facet_state: "adjusted", nist_likelihood: "very-low", nist_impact: "low",
                    approval_status: "approved", approved_by: "ao@example.com", approved_at: Time.utc(2026, 11, 19))
    end
    let(:doc) { described_class.new(boundary, runner: runner).export }

    it "returns a POA&M that passes SPARC's OSCAL schema validation" do
      expect(doc).to have_key("plan-of-action-and-milestones")
    end

    it "sets the NIST risk status the user picked, over hdf's open/closed" do
      expect(risk_for(doc, "CVE-2026-0001")["status"]).to eq("open")
      expect(risk_for(doc, "CVE-2026-0002")["status"]).to eq("deviation-approved")
    end

    it "adds the NIST risk prop in NIST's namespace" do
      props = risk_for(doc, "CVE-2026-0002")["props"]
      expect(props).to include({ "name" => "false-positive", "value" => "yes" })
      expect(risk_for(doc, "CVE-2026-0001")["props"]).to include({ "name" => "accepted", "value" => "yes" })
    end

    it "rates likelihood, impact and the derived risk on SP 800-30's scale, with the picked state" do
      facets = risk_for(doc, "CVE-2026-0001")["characterizations"].first["facets"]
      expect(facets.map { |f| [ f["name"], f["value"] ] })
        .to eq([ %w[likelihood moderate], %w[impact high], %w[risk moderate] ])
      expect(facets).to all(include("system" => "http://csrc.nist.gov/ns/oscal",
                                    "props" => [ { "name" => "state", "value" => "initial" } ]))
    end

    it "says vendor dependency is a transfer, logged as a vendor check-in" do
      risk = risk_for(doc, "CVE-2026-0001")
      expect(risk["remediations"].first).to include("lifecycle" => "planned",
                                                    "props" => [ { "name" => "type", "value" => "transfer" } ])
      types = risk.dig("risk-log", "entries").flat_map { |e| Array(e["props"]).map { |p| p["value"] } }
      expect(types).to include("vendor-check-in")
    end

    it "logs an approved false positive as submitted, then approved, with response none" do
      risk = risk_for(doc, "CVE-2026-0002")
      expect(risk["remediations"].first["props"]).to eq([ { "name" => "type", "value" => "none" } ])
      types = risk.dig("risk-log", "entries").flat_map { |e| Array(e["props"]).map { |p| p["value"] } }
      expect(types).to eq(%w[dr-submission dr-approved])
    end

    it "attributes the rating to the person hdf recorded" do
      actor = risk_for(doc, "CVE-2026-0001")["characterizations"].first.dig("origin", "actors").first
      parties = doc.dig("plan-of-action-and-milestones", "metadata", "parties").map { |p| p["uuid"] }
      expect(actor["type"]).to eq("party")
      expect(parties).to include(actor["actor-uuid"])
    end

    it "produces the same document on every export" do
      again = described_class.new(boundary, runner: runner).export
      expect(risk_for(again, "CVE-2026-0001")).to eq(risk_for(doc, "CVE-2026-0001"))
    end
  end

  # Owner, 2026-11-19: never export without the NIST fields; fail loud with why.
  context "when a disposition was decided before the NIST fields existed" do
    before do
      dispositioned("CVE-2026-0001", kind: "poam", nist_likelihood: nil, nist_impact: nil)
      dispositioned("CVE-2026-0002", :without_nist, kind: "falsePositive")
    end

    it "refuses, naming each disposition and what it lacks" do
      expect { described_class.new(boundary, runner: runner).export }.to raise_error(described_class::MissingNistFields) do |e|
        expect(e.missing).to eq("CVE-2026-0001" => %i[nist_likelihood nist_impact],
                                "CVE-2026-0002" => FindingDisposition::NIST_FIELDS)
        expect(e.message).to include("2 dispositions lack", "CVE-2026-0001 (nist_likelihood, nist_impact)",
                                     "triage screen")
      end
      expect(runner).not_to have_received(:convert)
    end
  end

  describe "with the real hdf binary" do
    before do
      skip "hdf-cli not on PATH (see #835); run in the image or after script/dev/install-hdf.sh" \
        unless HdfSystemExportService.cli_available?
    end

    it "converts and completes one disposition of every kind into a valid POA&M" do
      FindingDisposition::KINDS.each_with_index do |kind, i|
        attrs = kind == "riskAdjustment" ? { adjusted_impact: 0.3 } : {}
        attrs[:linked_subject] = create(:attestation) if kind == "attestation"
        dispositioned("CVE-K#{i}", kind: kind, **attrs)
      end
      doc = described_class.new(boundary, runner: HdfRunner.new).export
      risks = doc.dig("plan-of-action-and-milestones", "risks")

      expect(risks.size).to eq(FindingDisposition::KINDS.size)
      expect(risks.map { |r| r["status"] }).to all(eq("deviation-requested"))
      expect(risks.map { |r| r["remediations"].first.dig("props", 0, "value") })
        .to match_array(FindingDisposition::KINDS.map { |k| DispositionVocabulary.for(k).response_type })
    end
  end
end
