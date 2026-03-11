require "rails_helper"

RSpec.describe CatalogImportService do
  let(:rev5_xml_path) { Rails.root.join("spec/fixtures/files/catalogs/NIST_SP-800-53_rev5_catalog.xml") }
  let(:rev5_json_path) { Rails.root.join("spec/fixtures/files/catalogs/NIST_SP-800-53_rev5_catalog.json") }
  let(:rev4_xml_path) { Rails.root.join("spec/fixtures/files/catalogs/NIST_SP-800-53_rev4_catalog.xml") }

  # ── Format detection ─────────────────────────────────────────────────────

  describe "#detect_format (via call)" do
    it "detects OSCAL XML catalogs" do
      file = File.open(rev5_xml_path)
      service = described_class.new(file, "NIST_SP-800-53_rev5_catalog.xml")
      expect(service.send(:detect_format)).to eq(:oscal_xml)
    end

    it "detects OSCAL JSON catalogs" do
      file = File.open(rev5_json_path)
      service = described_class.new(file, "NIST_SP-800-53_rev5_catalog.json")
      expect(service.send(:detect_format)).to eq(:oscal_json)
    end

    it "detects Rev 4 OSCAL XML catalogs" do
      file = File.open(rev4_xml_path)
      service = described_class.new(file, "NIST_SP-800-53_rev4_catalog.xml")
      expect(service.send(:detect_format)).to eq(:oscal_xml)
    end

    it "returns :unknown for unrecognised content" do
      file = StringIO.new("just some text")
      service = described_class.new(file, "random.txt")
      expect(service.send(:detect_format)).to eq(:unknown)
    end
  end

  # ── OSCAL XML import ─────────────────────────────────────────────────────

  describe "#import_oscal_xml (Rev 5)" do
    let(:result) do
      file = File.open(rev5_xml_path)
      described_class.call(file, "NIST_SP-800-53_rev5_catalog.xml")
    end

    it "creates a catalog with correct metadata" do
      catalog = result[:catalog]
      expect(catalog).to be_persisted
      expect(catalog.name).to include("NIST SP 800-53")
      expect(catalog.version).to eq("5.2.0")
      expect(catalog.oscal_version).to eq("1.1.3")
      expect(catalog.source).to eq("OSCAL")
    end

    it "imports all 20 NIST families" do
      expect(result[:families]).to eq(20)
    end

    it "imports controls with correct IDs, labels, and sort-ids" do
      result # trigger import
      ac1 = CatalogControl.find_by(control_id: "ac-1")
      expect(ac1).to be_present
      expect(ac1.label).to include("AC-1").or include("AC-01")
      expect(ac1.sort_id).to eq("ac-01")
      expect(ac1.title).to be_present
    end

    it "imports a large number of controls" do
      expect(result[:controls]).to be > 500
    end

    it "imports enhancements via recursion" do
      result # trigger import
      # AC-2(1) should be imported as ac-2.1
      enhancement = CatalogControl.find_by(control_id: "ac-2.1")
      expect(enhancement).to be_present
      expect(enhancement.title).to be_present
    end

    # ── Parameter extraction ──

    context "parameters" do
      before { result }

      let(:ac1) { CatalogControl.find_by(control_id: "ac-1") }

      it "populates params_data for controls with parameters" do
        expect(ac1.params_present?).to be true
        expect(ac1.params_list.size).to be >= 8
      end

      it "extracts parameter IDs" do
        ids = ac1.params_list.map { |p| p["id"] }
        expect(ids).to include("ac-01_odp.01", "ac-01_odp.03")
      end

      it "extracts parameter labels" do
        odp01 = ac1.params_list.find { |p| p["id"] == "ac-01_odp.01" }
        expect(odp01["label"]).to eq("personnel or roles")
      end

      it "extracts select/choice parameters" do
        odp03 = ac1.params_list.find { |p| p["id"] == "ac-01_odp.03" }
        expect(odp03["select"]).to be_present
        expect(odp03["select"]["how-many"]).to eq("one-or-more")
        expect(odp03["select"]["choice"]).to include("organization-level",
                                                      "mission/business process-level",
                                                      "system-level")
      end

      it "extracts parameter guidelines" do
        odp04 = ac1.params_list.find { |p| p["id"] == "ac-01_odp.04" }
        expect(odp04["label"]).to eq("official")
        expect(odp04["guidelines"]).to be_present
        expect(odp04["guidelines"].first["prose"]).to include("official")
      end

      it "extracts parameter props" do
        odp03 = ac1.params_list.find { |p| p["id"] == "ac-01_odp.03" }
        expect(odp03["props"]).to be_present
        alt_id = odp03["props"].find { |p| p["name"] == "alt-identifier" }
        expect(alt_id["value"]).to eq("ac-1_prm_2")
      end

      it "extracts aggregate-type params" do
        prm1 = ac1.params_list.find { |p| p["id"] == "ac-1_prm_1" }
        expect(prm1).to be_present
        expect(prm1["label"]).to eq("organization-defined personnel or roles")
        agg_props = prm1["props"]&.select { |p| p["name"] == "aggregates" }
        expect(agg_props).to be_present
        expect(agg_props.size).to eq(2)
      end
    end

    # ── Statement / guidance ──

    context "guidance data" do
      before { result }

      it "extracts statement prose" do
        ac1 = CatalogControl.find_by(control_id: "ac-1")
        expect(ac1.guidance_data["statement"]).to be_present
      end
    end

    # ── Re-import (idempotent) ──

    context "re-import with existing catalog" do
      it "updates existing catalog without duplicating" do
        first_result = described_class.call(File.open(rev5_xml_path), "NIST_SP-800-53_rev5_catalog.xml")
        catalog = first_result[:catalog]

        second_result = described_class.call(
          File.open(rev5_xml_path),
          "NIST_SP-800-53_rev5_catalog.xml",
          existing_catalog: catalog
        )

        expect(second_result[:catalog].id).to eq(catalog.id)
        expect(ControlCatalog.where(id: catalog.id).count).to eq(1)
      end
    end
  end

  # ── OSCAL XML import (Rev 4) ─────────────────────────────────────────────

  describe "#import_oscal_xml (Rev 4)" do
    let(:result) do
      file = File.open(rev4_xml_path)
      described_class.call(file, "NIST_SP-800-53_rev4_catalog.xml")
    end

    it "creates a catalog successfully" do
      expect(result[:catalog]).to be_persisted
    end

    it "imports families" do
      expect(result[:families]).to be >= 18
    end

    it "imports controls" do
      expect(result[:controls]).to be > 200
    end
  end

  # ── OSCAL JSON import (regression) ───────────────────────────────────────

  describe "#import_oscal_json (regression)" do
    let(:result) do
      file = File.open(rev5_json_path)
      described_class.call(file, "NIST_SP-800-53_rev5_catalog.json")
    end

    it "still imports correctly" do
      expect(result[:catalog]).to be_persisted
      expect(result[:families]).to eq(20)
      expect(result[:controls]).to be > 300
    end

    it "preserves params_data for JSON controls" do
      result
      ac1 = CatalogControl.find_by(control_id: "ac-1")
      expect(ac1.params_present?).to be true
      expect(ac1.params_list.size).to be >= 2
    end

    it "preserves select/choice in JSON params" do
      result
      ac1 = CatalogControl.find_by(control_id: "ac-1")
      select_params = ac1.params_list.select { |p| p["select"].present? }
      expect(select_params).to be_present
    end
  end

  # ── XML parameter helper unit tests ──────────────────────────────────────

  describe "#oscal_xml_collect_params" do
    let(:service) { described_class.new(StringIO.new(""), "test.xml") }

    it "extracts a simple label param from XML" do
      xml = Nokogiri::XML(<<~XML).at_xpath("//control")
        <catalog><control id="test-1">
          <param id="test-1_odp.01">
            <label>frequency</label>
          </param>
        </control></catalog>
      XML

      params = service.send(:oscal_xml_collect_params, xml)
      expect(params.size).to eq(1)
      expect(params.first["id"]).to eq("test-1_odp.01")
      expect(params.first["label"]).to eq("frequency")
    end

    it "extracts a select param with choices" do
      xml = Nokogiri::XML(<<~XML).at_xpath("//control")
        <catalog><control id="test-1">
          <param id="test-1_odp.02">
            <select how-many="one-or-more">
              <choice>daily</choice>
              <choice>weekly</choice>
              <choice>monthly</choice>
            </select>
          </param>
        </control></catalog>
      XML

      params = service.send(:oscal_xml_collect_params, xml)
      expect(params.size).to eq(1)
      p = params.first
      expect(p["select"]["how-many"]).to eq("one-or-more")
      expect(p["select"]["choice"]).to eq(%w[daily weekly monthly])
    end

    it "extracts a param with guideline" do
      xml = Nokogiri::XML(<<~XML).at_xpath("//control")
        <catalog><control id="test-1">
          <param id="test-1_odp.03">
            <label>officials</label>
            <guideline><p>officials managing the policy are defined</p></guideline>
          </param>
        </control></catalog>
      XML

      params = service.send(:oscal_xml_collect_params, xml)
      expect(params.first["guidelines"]).to be_present
      expect(params.first["guidelines"].first["prose"]).to include("officials managing")
    end

    it "extracts param props" do
      xml = Nokogiri::XML(<<~XML).at_xpath("//control")
        <catalog><control id="test-1">
          <param id="test-1_odp.04">
            <prop name="alt-identifier" value="test-1_prm_1"/>
            <prop name="label" class="sp800-53a" value="TEST-01_ODP[04]"/>
          </param>
        </control></catalog>
      XML

      params = service.send(:oscal_xml_collect_params, xml)
      expect(params.first["props"].size).to eq(2)
      alt = params.first["props"].find { |p| p["name"] == "alt-identifier" }
      expect(alt["value"]).to eq("test-1_prm_1")
      label_prop = params.first["props"].find { |p| p["name"] == "label" }
      expect(label_prop["class"]).to eq("sp800-53a")
    end

    it "returns empty array when no params present" do
      xml = Nokogiri::XML(<<~XML).at_xpath("//control")
        <catalog><control id="test-1">
          <title>No Params</title>
        </control></catalog>
      XML

      params = service.send(:oscal_xml_collect_params, xml)
      expect(params).to eq([])
    end
  end
end
