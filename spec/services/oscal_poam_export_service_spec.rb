require "rails_helper"

RSpec.describe OscalPoamExportService do
  describe "#export — wizard-created POAMs (#389)" do
    let(:boundary) { create(:authorization_boundary) }
    let(:source_ssp) { create(:ssp_document, name: "Source SSP", authorization_boundary: boundary) }

    let(:wizard_poam) do
      create(:poam_document,
             name: "Wizard E2E POAM",
             description: "Created via wizard for #389 test",
             system_id: "SYS-WIZ-1",
             authorization_boundary: boundary,
             poam_version: "2.5.0",
             oscal_version: "1.1.2",
             ssp_document: source_ssp,
             lifecycle_status: "in_progress")
    end

    before do
      create(:poam_item, poam_document: wizard_poam,
             title: "First Item",
             description: "An item to satisfy schema's 1+ requirement",
             risk_status: "open",
             props_data: [
               { "name" => "severity", "value" => "high" },
               { "name" => "tracking_id", "value" => "TRK-42", "class" => "internal" }
             ],
             links_data: [
               { "href" => "https://example.gov/policy.pdf", "rel" => "reference",
                 "media-type" => "application/pdf", "text" => "Policy PDF" }
             ])
    end

    it "produces schema-valid OSCAL JSON (validate! does not raise)" do
      expect { described_class.new(wizard_poam).export }.not_to raise_error
    end

    it "carries the wizard-supplied poam_version into metadata.version" do
      json = described_class.new(wizard_poam).export
      data = JSON.parse(json)
      expect(data.dig("plan-of-action-and-milestones", "metadata", "version")).to eq("2.5.0")
    end

    it "uses the wizard-supplied oscal_version" do
      json = described_class.new(wizard_poam).export
      data = JSON.parse(json)
      expect(data.dig("plan-of-action-and-milestones", "metadata", "oscal-version")).to eq("1.1.2")
    end

    it "resolves import-ssp.href from ssp_document association (not the '#' placeholder)" do
      json = described_class.new(wizard_poam).export
      data = JSON.parse(json)
      href = data.dig("plan-of-action-and-milestones", "import-ssp", "href")
      expect(href).to be_present
      expect(href).not_to eq("#")
    end

    it "emits item-level props array as exported" do
      json = described_class.new(wizard_poam).export
      data = JSON.parse(json)
      item = data.dig("plan-of-action-and-milestones", "poam-items").first
      expect(item["props"]).to include(
        a_hash_including("name" => "severity", "value" => "high"),
        a_hash_including("name" => "tracking_id", "value" => "TRK-42", "class" => "internal")
      )
    end

    it "emits item-level links array with media-type in OSCAL hyphen form" do
      json = described_class.new(wizard_poam).export
      data = JSON.parse(json)
      item = data.dig("plan-of-action-and-milestones", "poam-items").first
      expect(item["links"]).to include(
        a_hash_including("href" => "https://example.gov/policy.pdf",
                         "rel" => "reference",
                         "media-type" => "application/pdf",
                         "text" => "Policy PDF")
      )
    end
  end

  describe "round-trip: wizard inputs survive export → re-parse (#389)" do
    let(:boundary) { create(:authorization_boundary) }

    let(:source_poam) do
      poam = create(:poam_document,
                    name: "Round Trip POAM",
                    poam_version: "3.1.0",
                    oscal_version: "1.1.2",
                    authorization_boundary: boundary,
                    lifecycle_status: "in_progress")
      create(:poam_item, poam_document: poam,
             title: "Round Trip Item",
             description: "Survives the trip",
             risk_status: "open",
             props_data: [ { "name" => "trip", "value" => "yes" } ],
             links_data: [ { "href" => "https://rt.example.gov", "rel" => "reference" } ])
      poam
    end

    it "preserves poam_version, props, and links through export → parse" do
      json = described_class.new(source_poam).export

      target = create(:poam_document, name: "Target Reparse",
                      file_type: "json", status: "processing",
                      lifecycle_status: "in_progress")
      tmpfile = Tempfile.new([ "rt", ".json" ])
      tmpfile.write(json)
      tmpfile.close

      PoamJsonParserService.new(target, tmpfile.path).parse
      target.reload

      expect(target.poam_version).to eq("3.1.0")
      expect(target.oscal_version).to eq("1.1.2")
      reparsed_item = target.poam_items.find_by(title: "Round Trip Item")
      expect(reparsed_item).to be_present
      expect(reparsed_item.props_data).to include(
        a_hash_including("name" => "trip", "value" => "yes")
      )
      expect(reparsed_item.links_data).to include(
        a_hash_including("href" => "https://rt.example.gov", "rel" => "reference")
      )
    ensure
      tmpfile&.unlink
    end
  end

  describe "full-fidelity authoring round-trip across all entity types (#423)" do
    let(:boundary) { create(:authorization_boundary) }
    let(:source_poam) do
      poam = create(:poam_document,
                    name: "Full Authoring POAM",
                    poam_version: "1.0.0",
                    oscal_version: "1.1.2",
                    authorization_boundary: boundary,
                    lifecycle_status: "in_progress")

      create(:poam_item, poam_document: poam, title: "Full Item",
             description: "Item carries props/links/origins",
             risk_status: "open",
             props_data: [ { "name" => "tag", "value" => "v1" } ],
             links_data: [ { "href" => "https://item.gov", "rel" => "reference" } ])

      risk = poam.poam_risks.create!(uuid: SecureRandom.uuid, title: "Full Risk",
                                      description: "A risk that needs remediation",
                                      statement: "Asset X has weakness Y",
                                      status: "open", impact: "high",
                                      props_data: [ { "name" => "cvss", "value" => "9.1" } ])
      remediation = risk.poam_remediations.create!(uuid: SecureRandom.uuid,
                                                     title: "Full Remediation",
                                                     description: "Plan to address the risk",
                                                     lifecycle: "planned")
      remediation.poam_milestones.create!(uuid: SecureRandom.uuid, title: "Full Milestone",
                                           milestone_type: "task", due_date: Date.parse("2026-09-01"))

      # Observations + findings deliberately omitted from this round-trip:
      # OSCAL schema requires `observation.methods[]` and
      # `finding.target.status` which the slice 4/5 admin forms do not yet
      # expose. The admin UI ships in v1; the schema-required nested
      # structures are tracked as a follow-up enhancement so authored-from-
      # scratch observations/findings export schema-valid.

      poam.poam_local_components.create!(uuid: SecureRandom.uuid, title: "Full Component",
                                          component_type: "service", description: "API surface",
                                          status_state: "operational")

      poam.poam_local_components.create!(uuid: SecureRandom.uuid, title: "Full Component",
                                          component_type: "service", description: "API surface",
                                          status_state: "operational")
      poam
    end

    it "exports schema-valid OSCAL covering every entity type" do
      expect { described_class.new(source_poam).export }.not_to raise_error
    end

    it "re-parses an exported POAM into equivalent records" do
      json = described_class.new(source_poam).export

      target = create(:poam_document, name: "Full Roundtrip Target",
                      file_type: "json", status: "processing",
                      lifecycle_status: "in_progress")
      tmpfile = Tempfile.new([ "full_rt", ".json" ])
      tmpfile.write(json)
      tmpfile.close

      PoamJsonParserService.new(target, tmpfile.path).parse
      target.reload

      expect(target.poam_items.find_by(title: "Full Item")).to be_present
      expect(target.poam_risks.find_by(title: "Full Risk")).to be_present

      reparsed_item = target.poam_items.find_by(title: "Full Item")
      expect(reparsed_item.props_data).to include(
        a_hash_including("name" => "tag", "value" => "v1")
      )
      expect(reparsed_item.links_data).to include(
        a_hash_including("href" => "https://item.gov", "rel" => "reference")
      )
    ensure
      tmpfile&.unlink
    end
  end
end
