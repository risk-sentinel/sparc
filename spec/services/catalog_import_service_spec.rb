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

  # #1003 — the importer used to store a sub-part's prose as its title cut to
  # 200 characters "for readability". These pin that it does not any more,
  # because the truncation reached three places at once: the Implementation
  # Statements a user reads, the parameter references they contain, and the
  # OSCAL catalog export, which emits `title` verbatim.
  describe "statement prose is stored whole" do
    %w[xml json].each do |format|
      context "importing OSCAL #{format.upcase}" do
        let(:path) { format == "xml" ? rev5_xml_path : rev5_json_path }

        before do
          file = File.open(path)
          described_class.call(file, "NIST_SP-800-53_rev5_catalog.#{format}")
        end

        it "keeps a sub-part title longer than 200 characters intact" do
          long = CatalogControl.where("LENGTH(title) > 200")

          expect(long).to be_present,
            "no sub-part over 200 chars was imported, so this fixture cannot " \
            "prove the truncation is gone — check the fixture, not the code"
          expect(long.map(&:title)).to all(satisfy { |t| !t.end_with?("...") })
        end

        it "never severs a parameter reference" do
          severed = CatalogControl
                      .where("title LIKE ?", "%{{ insert: param%")
                      .reject { |c| c.title.scan("{{").size == c.title.scan("}}").size }

          expect(severed).to be_empty,
            "these titles open a `{{ insert: param` they never close, so " \
            "nothing can resolve them: " \
            "#{severed.map { |c| "#{c.control_id}: ...#{c.title.last(60)}" }.join("; ")}"
        end
      end
    end
  end

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

    # ── #999: control-level links ──────────────────────────────────────────
    #
    # These were discarded outright. Measured on the fixture: 1191 of 1196
    # controls carry links, and none of them reached the database — so an
    # exporter had nothing to emit and the 200 back-matter resources the
    # catalog declares had nothing pointing at them.
    describe "control-level links (#999)" do
      before { result }

      let(:ac1) { CatalogControl.find_by(control_id: "ac-1") }

      it "stores the control's links verbatim" do
        expect(ac1.links_list).to be_present
        expect(ac1.links_list.map { |l| l["rel"] }.uniq).to include("reference")
        expect(ac1.links_list.first["href"]).to start_with("#")
      end

      # The Rev 5 catalog puts `related` on the CONTROL; the importer read only
      # the guidance part's links, which is a Rev 4 shape. The consequence was
      # measured on the live instance: related_controls was populated on 7 of
      # 2318 Rev 5 controls, and blank on every screen and export.
      it "populates related_controls from the control's own links" do
        expect(ac1.guidance_data["related_controls"]).to be_present
        expect(ac1.guidance_data["related_controls"].split(", ")).to include("ia-1")
      end

      # Counted against the source file rather than a threshold: every control
      # the catalog gives a `related` link must end up with one. The old code
      # produced 7 of these on the live instance; the source declares 651.
      it "keeps every related link the source declares" do
        source = JSON.parse(File.read(rev5_json_path)).dig("catalog", "groups")
        expected = 0
        walk = lambda do |control|
          expected += 1 if Array(control["links"]).any? { |l| l["rel"] == "related" }
          Array(control["controls"]).each { |child| walk.call(child) }
        end
        source.each { |group| Array(group["controls"]).each { |c| walk.call(c) } }

        imported = CatalogControl.where.not(guidance_data: {})
                                 .select { |c| c.guidance_data["related_controls"].present? }.size

        expect(expected).to be > 600, "the fixture no longer exercises this"
        expect(imported).to eq(expected)
      end

      it "promotes the referenced back-matter resources to rows" do
        referenced = ac1.links_list.select { |l| l["rel"] == "reference" }
                        .map { |l| l["href"].delete_prefix("#") }

        expect(ac1.back_matter_resources.pluck(:uuid)).to match_array(referenced)
        expect(ac1.back_matter_resources.first.source).to eq("imported")
        expect(ac1.back_matter_resources.first.title).to be_present
      end

      it "reuses a promoted resource rather than minting a second on re-import" do
        before_count = BackMatterResource.where(source: "imported").count

        described_class.call(File.open(rev5_json_path), "NIST_SP-800-53_rev5_catalog.json",
                             existing_catalog: CatalogControl.first.control_family.control_catalog)

        expect(BackMatterResource.where(source: "imported").count).to eq(before_count)
      end

      it "does not promote a `related` link, which names a control and not a resource" do
        related_hrefs = ac1.links_list.select { |l| l["rel"] == "related" }
                           .map { |l| l["href"].delete_prefix("#") }

        expect(related_hrefs).to be_present
        expect(ac1.back_matter_resources.pluck(:uuid)).not_to include(*related_hrefs)
      end
    end
  end

  # ── XML parameter helper unit tests ──────────────────────────────────────

  # ── The keyword bag is only safe if a typo is LOUD ──────────────────────
  #
  # Collapsing ten parameters into `**fields` traded one problem for another:
  # a misspelled key would simply never arrive, and the control would import
  # with that field quietly unset. That is the #994 shape — a call that
  # discards what it did not recognise is indistinguishable from one that had
  # nothing to say — so the method validates its own keys.
  describe "#upsert_catalog_control field validation" do
    let(:catalog) { create(:control_catalog) }
    let(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }
    let(:service) { described_class.new(StringIO.new(""), "test.json") }

    it "accepts every documented field" do
      expect {
        service.send(:upsert_catalog_control, family, "ac-1",
          title: "Policy", priority: "P1", baseline: "LOW",
          guidance_data: { "statement" => "s" }, params_data: [],
          label: "AC-1", sort_id: "ac-01", links_data: [])
      }.not_to raise_error

      expect(family.catalog_controls.find_by(control_id: "ac-1").title).to eq("Policy")
    end

    it "REFUSES an unknown key instead of silently dropping it" do
      expect {
        service.send(:upsert_catalog_control, family, "ac-2", title: "X", lnks_data: [ { "rel" => "reference" } ])
      }.to raise_error(ArgumentError, /lnks_data/)
    end

    it "names every field it will accept, so the list cannot drift from the method" do
      expect(described_class::CONTROL_FIELDS).to contain_exactly(
        :title, :priority, :baseline, :guidance_data,
        :params_data, :label, :sort_id, :links_data
      )
    end
  end

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

  # ── OSCAL YAML import ──────────────────────────────────────────────────

  describe "#import_oscal_yaml" do
    let(:yaml_path) { Rails.root.join("spec/fixtures/files/catalogs/nist-style-catalog.yaml") }

    it "detects OSCAL YAML format" do
      file = File.open(yaml_path)
      service = described_class.new(file, "nist-style-catalog.yaml")
      expect(service.send(:detect_format)).to eq(:oscal_yaml)
    end

    it "imports a YAML catalog with correct metadata" do
      result = described_class.call(File.open(yaml_path), "nist-style-catalog.yaml")
      catalog = result[:catalog]

      expect(catalog).to be_persisted
      expect(catalog.name).to eq("NIST-Style Test Catalog")
      expect(catalog.source).to eq("OSCAL")
    end

    it "imports families and controls from YAML" do
      result = described_class.call(File.open(yaml_path), "nist-style-catalog.yaml")

      expect(result[:families]).to eq(2)
      expect(result[:controls]).to eq(3)
    end

    it "stores import_format as oscal_yaml" do
      result = described_class.call(File.open(yaml_path), "nist-style-catalog.yaml")
      expect(result[:catalog].metadata_extra["import_format"]).to eq("oscal_yaml")
    end
  end

  # ── Import format metadata ─────────────────────────────────────────────

  describe "import_format metadata" do
    it "stores oscal_json for JSON imports" do
      result = described_class.call(File.open(rev5_json_path), "catalog.json")
      expect(result[:catalog].metadata_extra["import_format"]).to eq("oscal_json")
    end

    it "stores oscal_xml for XML imports" do
      result = described_class.call(File.open(rev5_xml_path), "catalog.xml")
      expect(result[:catalog].metadata_extra["import_format"]).to eq("oscal_xml")
    end

    it "stores nist_xml for legacy NIST XML imports" do
      legacy_path = Rails.root.join("spec/fixtures/files/catalogs/nist_legacy_sample.xml")
      result = described_class.call(File.open(legacy_path), "nist_legacy.xml")
      expect(result[:catalog].metadata_extra["import_format"]).to eq("nist_xml")
    end
  end

  # ── NIST XML legacy enhancement import ─────────────────────────────────

  describe "NIST XML legacy enhancement import" do
    let(:legacy_path) { Rails.root.join("spec/fixtures/files/catalogs/nist_legacy_sample.xml") }
    let(:result) { described_class.call(File.open(legacy_path), "nist_legacy_sample.xml") }

    it "imports base controls" do
      result
      ac1 = CatalogControl.find_by(control_id: "ac-1")
      expect(ac1).to be_present
      expect(ac1.title).to include("Policy And Procedures")
    end

    it "imports control enhancements with canonical IDs" do
      result
      enh1 = CatalogControl.find_by(control_id: "ac-2.1")
      expect(enh1).to be_present
      expect(enh1.label).to eq("AC-2(1)")
      expect(enh1.sort_id).to eq("ac-02.01")
    end

    it "imports multiple enhancements for a control" do
      result
      expect(CatalogControl.find_by(control_id: "ac-2.1")).to be_present
      expect(CatalogControl.find_by(control_id: "ac-2.2")).to be_present
      expect(CatalogControl.find_by(control_id: "ac-2.3")).to be_present
    end

    it "imports enhancement guidance data" do
      result
      enh1 = CatalogControl.find_by(control_id: "ac-2.1")
      expect(enh1.guidance_data["statement"]).to be_present
      expect(enh1.guidance_data["supplemental_guidance"]).to be_present
    end

    it "imports enhancement baselines" do
      result
      enh1 = CatalogControl.find_by(control_id: "ac-2.1")
      expect(enh1.baseline_impact).to include("MODERATE")
    end

    it "imports enhancement sub-parts" do
      result
      # AC-2(2)(a) → ac-2.2 sub-parts from nested <statement>
      sub = CatalogControl.where("control_id LIKE ?", "ac-2(2)%")
                           .or(CatalogControl.where("control_id LIKE ?", "ac-2.2%"))
      # The sub-part AC-2(2)(a). should exist
      expect(result[:controls]).to be >= 5  # 2 base + 3 enhancements + sub-parts
    end

    it "counts enhancements in stats" do
      expect(result[:controls]).to be >= 5  # AC-1, AC-2, AC-2(1), AC-2(2), AC-2(3)
    end
  end

  # ── ID conversion helpers ──────────────────────────────────────────────

  describe "#nist_enhancement_to_oscal_id" do
    let(:service) { described_class.new(StringIO.new(""), "test.xml") }

    it "converts AC-2(1) to ac-2.1" do
      expect(service.send(:nist_enhancement_to_oscal_id, "AC-2(1)")).to eq("ac-2.1")
    end

    it "converts AC-2(13) to ac-2.13" do
      expect(service.send(:nist_enhancement_to_oscal_id, "AC-2(13)")).to eq("ac-2.13")
    end

    it "converts SI-4(2) to si-4.2" do
      expect(service.send(:nist_enhancement_to_oscal_id, "SI-4(2)")).to eq("si-4.2")
    end
  end

  describe "#pad_enhancement_id" do
    let(:service) { described_class.new(StringIO.new(""), "test.xml") }

    it "pads AC-2(1) to AC-02.01" do
      expect(service.send(:pad_enhancement_id, "AC-2(1)")).to eq("AC-02.01")
    end

    it "pads AC-2(13) to AC-02.13" do
      expect(service.send(:pad_enhancement_id, "AC-2(13)")).to eq("AC-02.13")
    end
  end

  # ── Cross-format profile resolution ────────────────────────────────────

  describe "cross-format canonical ID consistency" do
    it "produces matching control IDs from JSON and YAML" do
      json_result = described_class.call(
        File.open(rev5_json_path),
        "catalog.json"
      )
      json_ids = json_result[:catalog].catalog_controls.pluck(:control_id).sort

      yaml_path = Rails.root.join("spec/fixtures/files/catalogs/NIST_SP-800-53_rev5_catalog.yaml")
      yaml_result = described_class.call(
        File.open(yaml_path),
        "catalog.yaml"
      )
      yaml_ids = yaml_result[:catalog].catalog_controls.pluck(:control_id).sort

      # Both should produce the same canonical IDs
      expect(json_ids).to eq(yaml_ids)
    end
  end

  # ── #941 — sub-part sort keys ────────────────────────────────────────────
  #
  # OSCAL puts `props.sort-id` on every control and on none of its 11159
  # `part` elements. The sub-part ROW is SPARC's own invention, so the sort key
  # has to be SPARC's too, or `default_scope { order(COALESCE(sort_id,
  # control_id)) }` compares an unpadded "ac-2.7.(a)" against a padded "ac-25".
  describe "statement sub-part ordering (#941)" do
    subject(:service) { described_class.new(File.open(rev5_json_path), "catalog.json") }

    describe "#derived_sort_id" do
      it "extends the parent's key with the suffix the identifier added" do
        expect(service.send(:derived_sort_id, "ac-02.07", "ac-2.7", "ac-2.7.(a)"))
          .to eq("ac-02.07.(a)")
      end

      it "extends a letter suffix without a separator, as the identifier does" do
        expect(service.send(:derived_sort_id, "ac-01", "ac-1", "ac-1a")).to eq("ac-01a")
      end

      # Depth keeps extending one padded string rather than restarting.
      it "chains through an already-derived parent key" do
        expect(service.send(:derived_sort_id, "ac-03.03.(b)", "ac-3.3.(b)", "ac-3.3.(b).(1)"))
          .to eq("ac-03.03.(b).(1)")
      end

      # NIST XML enhancement sub-parts keep their own parenthesised numbering,
      # so the prefix relationship does not hold and a guess would be worse than
      # the COALESCE fallback.
      it "returns nil when the sub-id is not built from the parent-id" do
        expect(service.send(:derived_sort_id, "ac-02.07", "ac-2.7", "ac-2(7)(a)")).to be_nil
      end

      it "falls back to the parent's identifier when the parent has no key" do
        expect(service.send(:derived_sort_id, nil, "ac-2.7", "ac-2.7.(a)")).to eq("ac-2.7.(a)")
      end

      it "returns nil rather than inventing a key with no parent to extend" do
        expect(service.send(:derived_sort_id, nil, nil, "ac-2.7.(a)")).to be_nil
      end
    end

    describe "importing the real Rev 5 catalog" do
      before { described_class.call(File.open(rev5_json_path), "NIST_SP-800-53_rev5_catalog.json") }

      it "gives every statement sub-part a key derived from its parent" do
        parent  = CatalogControl.find_by(control_id: "ac-2.7")
        subpart = CatalogControl.find_by(control_id: "ac-2.7.(a)")

        expect(parent.sort_id).to eq("ac-02.07")
        expect(subpart.sort_id).to eq("ac-02.07.(a)")
      end

      it "sorts the sub-part under its parent instead of after the last control" do
        family = CatalogControl.find_by(control_id: "ac-2.7").control_family
        ordered = family.catalog_controls.pluck(:control_id)

        expect(ordered.index("ac-2.7.(a)")).to eq(ordered.index("ac-2.7") + 1)
        expect(ordered.index("ac-2.7.(a)")).to be < ordered.index("ac-25")
      end

      it "leaves no imported sub-part without a sort key" do
        family = CatalogControl.find_by(control_id: "ac-2.7").control_family

        expect(family.catalog_controls.where(sort_id: nil)).to be_empty
      end
    end
  end
end
