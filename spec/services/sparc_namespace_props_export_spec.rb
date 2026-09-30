# frozen_string_literal: true

require "rails_helper"
require "json_schemer"

# #1154 — SSP, POA&M and SAR exports carry the SPARC-namespace props Horizon
# reads, wherever SPARC holds the data; the validated export refuses a document
# whose props would not pass Horizon's schema; and a document carrying them is
# STILL valid NIST OSCAL at 1.2.3 (the owner's condition, D1: "Add data points
# that can be added without violating OSCAL schema").
#
# Schema validity is checked against the tracked 1.2.3 schema files directly,
# not through OscalSchemaValidationService's `version:` argument, which in a test
# database with no schema rows reports the version asked for whatever it
# actually loaded.
RSpec.describe "SPARC-namespace props on export (#1154)" do
  let(:ns) { OscalNamespace.uri(:sparc) }
  let(:organization) { create(:organization) }
  let(:boundary) do
    create(:authorization_boundary, organization: organization,
                                    security_objective_confidentiality: "fips-199-high",
                                    security_objective_integrity: "fips-199-moderate",
                                    security_objective_availability: "fips-199-low",
                                    next_decision_date: "2026-10-11")
  end

  def sparc_props(props, name = nil)
    Array(props).select { |p| p["ns"] == ns && (name.nil? || p["name"] == name) }
  end

  def value_of(props, name) = sparc_props(props, name).map { |p| p["value"] }

  def nist_errors(schema_file, data)
    raw = JSON.parse(Rails.root.join("lib/oscal_schemas", schema_file).read)
    expect(raw["$id"]).to include("/1.2.3/"), "expected the tracked schema to be NIST OSCAL 1.2.3, got #{raw['$id']}"
    JSONSchemer.schema(OscalSchema.preprocess_schema(raw)).validate(data).first(5).map { |e| e["error"] }
  end

  describe "SSP" do
    let(:ssp) do
      create(:ssp_document, :enriched, name: "Props SSP", oscal_version: "1.2.3", authorization_boundary: boundary)
    end

    before do
      create(:ssp_component, ssp_document: ssp, component_type: "software", title: "App", description: "App server")
      create(:ssp_user, ssp_document: ssp, title: "System Owner", role_ids_data: [ "system-owner" ])
      create(:ssp_information_type, ssp_document: ssp, title: "Info", description: "Info type")
      create(:ssp_control, ssp_document: ssp, control_id: "ac-1", title: "Policy")
      ensure_control("ac-1")
    end

    let(:data) { JSON.parse(OscalSspExportService.new(ssp.reload).export) }
    let(:metadata) { data.dig("system-security-plan", "metadata") }

    it "emits node-type, parent-uuid, fips-199 and next-decision-date on metadata, from the boundary" do
      expect(value_of(metadata["props"], "node-type")).to eq([ "system" ])
      expect(value_of(metadata["props"], "parent-uuid")).to eq([ boundary.uuid ])
      # The boundary's high-water mark (one HIGH objective), not the SSP's own
      # `fips-199-moderate` — the boundary is the categorization's source.
      expect(value_of(metadata["props"], "fips-199")).to eq([ "high" ])
      expect(value_of(metadata["props"], "next-decision-date")).to eq([ "2026-10-11" ])
    end

    it "keeps the native security-sensitivity-level beside fips-199" do
      expect(data.dig("system-security-plan", "system-characteristics", "security-sensitivity-level"))
        .to eq("fips-199-moderate")
    end

    it "tags the organization party node-type organization" do
      party = metadata["parties"].find { |p| p["uuid"] == organization.uuid }
      expect(value_of(party["props"], "node-type")).to eq([ "organization" ])
    end

    it "is valid NIST OSCAL 1.2.3 with the props present" do
      expect(sparc_props(metadata["props"]).size).to eq(4)
      expect(nist_errors("oscal_ssp_schema.json", data)).to eq([])
    end

    it "replaces a stale imported value rather than emitting a second one" do
      ssp.update!(metadata_extra: (ssp.metadata_extra || {}).merge(
        "props" => [ { "name" => "parent-uuid", "ns" => ns, "value" => SecureRandom.uuid },
                     { "name" => "fips-199", "ns" => ns, "value" => "low" },
                     { "name" => "keep-me", "ns" => ns, "value" => "x" } ]
      ))

      expect(value_of(metadata["props"], "parent-uuid")).to eq([ boundary.uuid ])
      expect(value_of(metadata["props"], "fips-199")).to eq([ "high" ])
      expect(value_of(metadata["props"], "keep-me")).to eq([ "x" ])
    end

    it "omits next-decision-date when the boundary has none, and never invents one" do
      boundary.update!(next_decision_date: nil)

      expect(value_of(metadata["props"], "next-decision-date")).to eq([])
    end

    it "falls back to the SSP's own categorization when the boundary has none" do
      boundary.update_columns(security_objective_confidentiality: nil, security_objective_integrity: nil,
                              security_objective_availability: nil)

      expect(value_of(metadata["props"], "fips-199")).to eq([ "moderate" ])
    end

    it "emits no fips-199 and no parent-uuid for a boundary-less, uncategorized SSP — and still exports" do
      bare = build(:ssp_document, name: "Bare", oscal_version: "1.2.3", authorization_boundary: nil)
      bare.save!(validate: false)
      create(:ssp_control, ssp_document: bare, control_id: "ac-1")
      exported = JSON.parse(OscalSspExportService.new(bare.reload).export)
      props = exported.dig("system-security-plan", "metadata", "props")

      expect(value_of(props, "node-type")).to eq([ "system" ])
      expect(value_of(props, "fips-199")).to eq([])
      expect(value_of(props, "parent-uuid")).to eq([])
    end

    it "refuses the validated export when a SPARC-namespace prop is malformed" do
      ssp.update!(metadata_extra: (ssp.metadata_extra || {}).merge(
        "parties" => [ { "uuid" => SecureRandom.uuid, "type" => "person", "name" => "X",
                         "props" => [ { "name" => "node-type", "ns" => ns, "value" => "tenant" } ] } ]
      ))

      expect { OscalSspExportService.new(ssp.reload).export }
        .to raise_error(OscalValidationError, /SPARC-namespace props.*node-type/m)
      # The unvalidated path is for inspecting exactly such a document.
      expect { OscalSspExportService.new(ssp.reload).export_unvalidated }.not_to raise_error
    end

    it "runs the namespace rule on the validated path only" do
      allow(SparcNamespacePropsRule).to receive(:validate!).and_call_original

      OscalSspExportService.new(ssp.reload).export_unvalidated
      expect(SparcNamespacePropsRule).not_to have_received(:validate!)

      OscalSspExportService.new(ssp.reload).export
      expect(SparcNamespacePropsRule).to have_received(:validate!)
        .with(:ssp, anything, required_metadata: hash_including("node-type" => "system", "parent-uuid" => boundary.uuid))
    end

    describe "evidence in back-matter" do
      let(:attestation_evidence) do
        create(:evidence, :attestation, authorization_boundary: boundary, title: "Access review")
      end
      let(:attester) { attestation_evidence.attestations.first.attester_user }

      def resource_for(evidence)
        create(:back_matter_resource, resourceable: ssp, evidence: evidence, title: evidence.title)
        data.dig("system-security-plan", "back-matter", "resources").find { |r| r["title"] == evidence.title }
      end

      it "emits evidence-kind manual-attestation and signed-by the declared party that IS the attester" do
        ssp.update!(metadata_extra: (ssp.metadata_extra || {}).merge(
          "parties" => [ { "uuid" => attester.uuid, "type" => "person", "name" => "ISSO" } ]
        ))
        resource = resource_for(attestation_evidence)

        expect(value_of(resource["props"], "evidence-kind")).to eq([ "manual-attestation" ])
        expect(value_of(resource["props"], "signed-by")).to eq([ attester.uuid ])
        expect(nist_errors("oscal_ssp_schema.json", data)).to eq([])
      end

      it "resolves the attester by a declared person party's email" do
        party_uuid = SecureRandom.uuid
        ssp.update!(metadata_extra: (ssp.metadata_extra || {}).merge(
          "parties" => [ { "uuid" => party_uuid, "type" => "person", "name" => "ISSO",
                           "email-addresses" => [ attester.email.upcase ] } ]
        ))

        expect(value_of(resource_for(attestation_evidence)["props"], "signed-by")).to eq([ party_uuid ])
      end

      it "emits NO signed-by when the document declares no party for the attester" do
        expect(value_of(resource_for(attestation_evidence)["props"], "signed-by")).to eq([])
      end

      {
        "screenshot" => "screenshot", "scan_result" => "scan-report", "policy_document" => "document"
      }.each do |type, kind|
        it "maps evidence type #{type} to #{kind}" do
          evidence = create(:evidence, evidence_type: type, authorization_boundary: boundary, title: "E #{type}")
          expect(value_of(resource_for(evidence)["props"], "evidence-kind")).to eq([ kind ])
        end
      end

      %w[artifact log config_export test_result].each do |type|
        it "emits no evidence-kind for #{type}, which has no honest mapping" do
          evidence = create(:evidence, evidence_type: type, authorization_boundary: boundary, title: "E #{type}")
          expect(value_of(resource_for(evidence)["props"], "evidence-kind")).to eq([])
        end
      end
    end
  end

  describe "POA&M" do
    let(:poam) { create(:poam_document, authorization_boundary: boundary, oscal_version: "1.2.3") }
    let!(:risk) do
      create(:poam_risk, poam_document: poam, blocks_ato: true, condition_expires: Date.new(2026, 11, 1),
                         reopen_trigger: "score<0.85")
    end
    let!(:undecided) { create(:poam_risk, poam_document: poam) }

    before do
      item = create(:poam_item, poam_document: poam, title: "Item", description: "Item", risk_status: "open")
      create(:poam_item_risk, poam_item: item, poam_risk: risk)
    end

    let(:data) { JSON.parse(OscalPoamExportService.new(poam.reload).export) }
    let(:risks) { data.dig("plan-of-action-and-milestones", "risks") }

    it "emits blocks-ato, condition-expires and trigger from the columns" do
      props = risks.find { |r| r["uuid"] == risk.uuid }["props"]

      expect(value_of(props, "blocks-ato")).to eq([ "true" ])
      expect(value_of(props, "condition-expires")).to eq([ "2026-11-01" ])
      expect(value_of(props, "trigger")).to eq([ "score<0.85" ])
    end

    it "emits blocks-ato false as false — a decision, not an absence" do
      risk.update!(blocks_ato: false)
      expect(value_of(risks.find { |r| r["uuid"] == risk.uuid }["props"], "blocks-ato")).to eq([ "false" ])
    end

    it "emits nothing for an undecided risk (no empty props array either)" do
      expect(risks.find { |r| r["uuid"] == undecided.uuid }).not_to have_key("props")
    end

    it "tags the organization party and is valid NIST OSCAL 1.2.3" do
      party = data.dig("plan-of-action-and-milestones", "metadata", "parties").find { |p| p["uuid"] == organization.uuid }
      expect(value_of(party["props"], "node-type")).to eq([ "organization" ])
      expect(nist_errors("oscal_poam_schema.json", data)).to eq([])
    end

    # The columns are the one source of these three: a stale or malformed copy
    # left in props_data (an older import, the free-form props editor) is
    # replaced by the column value, never emitted beside it.
    it "replaces a stored copy of a column-owned prop with the column value" do
      risk.update_columns(props_data: [ { "name" => "condition-expires", "ns" => ns, "value" => "soon" } ])
      props = risks.find { |r| r["uuid"] == risk.uuid }["props"]

      expect(value_of(props, "condition-expires")).to eq([ "2026-11-01" ])
    end

    it "refuses the validated export when a stored risk prop is in the wrong place" do
      undecided.update_columns(props_data: [ { "name" => "fips-199", "ns" => ns, "value" => "high" } ])

      expect { OscalPoamExportService.new(poam.reload).export }
        .to raise_error(OscalValidationError, /fips-199\): belongs on SSP metadata/)
    end
  end

  describe "SAR" do
    let(:sar) { create(:sar_document, :enriched, authorization_boundary: boundary, oscal_version: "1.2.3") }
    let(:result) { create(:sar_result, sar_document: sar) }
    let!(:risk) { create(:sar_risk, sar_result: result, blocks_ato: true) }

    before do
      ensure_control("ac-1")
      create(:sar_control, sar_document: sar, control_id: "ac-1")
    end

    let(:data) { JSON.parse(OscalSarExportService.new(sar.reload).export) }

    it "emits blocks-ato on the SAR risk and stays valid NIST OSCAL 1.2.3" do
      exported = data.dig("assessment-results", "results").flat_map { |r| r["risks"] || [] }
                     .find { |r| r["uuid"] == risk.uuid }

      expect(value_of(exported["props"], "blocks-ato")).to eq([ "true" ])
      expect(nist_errors("oscal_assessment-results_schema.json", data)).to eq([])
    end

    it "passes a SAR risk's imported condition-expires through as issued (no SAR column owns it)" do
      risk.update_columns(props_data: [ { "name" => "condition-expires", "ns" => ns, "value" => "2026-12-01" } ])
      exported = data.dig("assessment-results", "results").flat_map { |r| r["risks"] || [] }
                     .find { |r| r["uuid"] == risk.uuid }

      expect(value_of(exported["props"], "condition-expires")).to eq([ "2026-12-01" ])
      expect(value_of(exported["props"], "blocks-ato")).to eq([ "true" ])
    end

    it "refuses the validated export for a malformed SAR risk prop" do
      risk.update_columns(props_data: [ { "name" => "trigger", "ns" => ns, "value" => "whenever" } ])

      expect { OscalSarExportService.new(sar.reload).export }.to raise_error(OscalValidationError, /trigger/)
    end
  end
end
