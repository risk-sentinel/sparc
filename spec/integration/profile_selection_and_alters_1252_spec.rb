# frozen_string_literal: true

require "rails_helper"

# #1252 — a profile that tailors by include-all, matching, with-child-controls,
# exclude-controls and alters imports with the selection and the text the
# profile states, in JSON, YAML and XML alike, and the resolved catalog, the
# requirement text and SSP generation all see the same tailoring.
#
# The catalog and profiles are invented (agency-style tailoring of an invented
# "ZZ" family). Expected selections are derived from the catalog, not pinned.
RSpec.describe "Profile selection and alters (#1252)" do
  let(:catalog_uuid) { SecureRandom.uuid }
  let(:catalog_name) { "Invented ZZ Controls #{SecureRandom.hex(3)}" }

  def item(id, label, prose) = { "id" => id, "name" => "item", "props" => [ { "name" => "label", "value" => label } ], "prose" => prose }

  def control(id, title, items, controls: nil)
    {
      "id" => id, "title" => title,
      "props" => [ { "name" => "label", "value" => id.upcase } ],
      "parts" => [ { "id" => "#{id}_smt", "name" => "statement", "parts" => items },
                   { "id" => "#{id}_gdn", "name" => "guidance", "prose" => "Guidance for #{id}." } ],
      "controls" => controls
    }.compact
  end

  let(:catalog_json) do
    { "catalog" => {
      "uuid" => catalog_uuid,
      "metadata" => { "title" => catalog_name, "last-modified" => "2026-10-22T00:00:00Z", "version" => "1", "oscal-version" => "1.2.3" },
      "groups" => [ { "id" => "zz", "title" => "Invented", "controls" => [
        control("zz-1", "Policy", [ item("zz-1_smt.a", "a.", "Write a policy."), item("zz-1_smt.b", "b.", "Review it.") ],
                controls: [ control("zz-1.1", "Policy Review", [ item("zz-1.1_smt.a", "a.", "Review yearly.") ]),
                            control("zz-1.2", "Policy Approval", [ item("zz-1.2_smt.a", "a.", "Approve it.") ]) ]),
        control("zz-2", "Inventory", [ item("zz-2_smt.a", "a.", "Keep an inventory.") ],
                controls: [ control("zz-2.1", "Automated Inventory", [ item("zz-2.1_smt.a", "a.", "Automate it.") ]) ]),
        control("zz-10", "Logging", [ item("zz-10_smt.a", "a.", "Log events.") ])
      ] } ]
    } }
  end

  let!(:catalog) do
    path = Rails.root.join("tmp", "zz-catalog-#{SecureRandom.hex(4)}.json")
    File.write(path, JSON.generate(catalog_json))
    CatalogImportService.call(File.open(path), File.basename(path))[:catalog]
  ensure
    FileUtils.rm_f(path)
  end

  # The catalog's controls in order, read back from what the import stored.
  let(:catalog_ids) { CatalogControlTree.for(catalog).map(&:first) }

  let(:back_matter) do
    { "resources" => [ { "uuid" => "aaaaaaaa-0000-4000-8000-000000000001", "title" => catalog_name,
                         "rlinks" => [ { "href" => "zz-catalog-#{catalog_uuid}.json" } ] } ] }
  end

  def profile_json(import, modify: nil)
    { "profile" => {
      "uuid" => SecureRandom.uuid,
      "metadata" => { "title" => "Agency ZZ Baseline", "last-modified" => "2026-10-22T00:00:00Z", "version" => "1", "oscal-version" => "1.2.3" },
      "imports" => [ import.merge("href" => "#aaaaaaaa-0000-4000-8000-000000000001") ],
      "modify" => modify,
      "back-matter" => back_matter
    }.compact }
  end

  def import_profile(data, format: "json")
    content = case format
    when "json" then JSON.generate(data)
    when "yaml" then YAML.dump(data)
    when "xml"  then data # already XML text
    end
    path = Rails.root.join("tmp", "zz-profile-#{SecureRandom.hex(4)}.#{format}")
    File.write(path, content)
    doc = create(:profile_document, status: "processing", file_type: format, original_filename: File.basename(path), control_catalog: nil)
    parser = { "json" => ProfileJsonParserService, "yaml" => ProfileYamlParserService, "xml" => ProfileXmlParserService }[format]
    parser.new(doc, path.to_s).parse
    doc.reload
  ensure
    FileUtils.rm_f(path) if path
  end

  def selected(doc) = doc.profile_controls.order(:row_order).pluck(:control_id)

  describe "selection" do
    it "include-all with exclude-controls selects the catalog minus the exclusions" do
      doc = import_profile(profile_json({ "include-all" => {}, "exclude-controls" => [ { "with-ids" => %w[zz-10] } ] }))
      expect(catalog_ids).to include("zz-10", "zz-1.1")
      expect(selected(doc)).to eq(catalog_ids - %w[zz-10])
    end

    it "with-child-controls brings the enhancements in with their parent" do
      doc = import_profile(profile_json({ "include-controls" => [ { "with-ids" => %w[zz-2], "with-child-controls" => "yes" } ] }))
      expect(selected(doc)).to eq(catalog_ids.select { |id| id == "zz-2" || id.start_with?("zz-2.") })
    end

    it "matching selects by pattern" do
      doc = import_profile(profile_json({ "include-controls" => [ { "matching" => [ { "pattern" => "zz-1.*" } ] } ] }))
      expect(selected(doc)).to eq(catalog_ids.select { |id| File.fnmatch("zz-1.*", id) })
    end

    it "links every selected control to the catalog" do
      doc = import_profile(profile_json({ "include-all" => {} }))
      expect(doc.profile_controls.pluck(:source_catalog_id).uniq).to eq([ catalog.id ])
      expect(doc.import_metadata.dig("imports", 0, "matched_by")).to eq("uuid")
    end

    it "reports a named id the catalog does not have" do
      doc = import_profile(profile_json({ "include-controls" => [ { "with-ids" => %w[zz-1 zz-99] } ] }))
      expect(doc.import_metadata.dig("imports", 0, "unknown_ids")).to eq(%w[zz-99])
    end

    it "an import no catalog matches keeps its named ids and reports the selectors it cannot apply" do
      data = profile_json({ "include-all" => {}, "include-controls" => [ { "with-ids" => %w[zz-1 zz-2] } ],
                            "exclude-controls" => [ { "with-ids" => %w[zz-2] } ] })
      data["profile"]["back-matter"]["resources"][0].merge!("title" => "Never loaded", "rlinks" => [ { "href" => "https://example.com/x.json" } ])
      doc = import_profile(data)

      expect(selected(doc)).to eq(%w[zz-1])
      expect(doc.import_metadata.dig("unlinked_imports", 0, "unresolved_selectors")).to eq(%w[include-all])
    end
  end

  describe "alters" do
    let(:added) { { "id" => "zz-1_smt.c", "name" => "item", "props" => [ { "name" => "label", "value" => "c." } ], "prose" => "Brief staff annually." } }
    let(:modify) do
      { "alters" => [ { "control-id" => "zz-1",
                        "removes" => [ { "by-id" => "zz-1_smt.b" } ],
                        "adds" => [ { "position" => "after", "by-id" => "zz-1_smt.a", "parts" => [ added ] },
                                    { "position" => "starting", "props" => [ { "name" => "priority", "value" => "P1" } ] } ] } ] }
    end
    let(:doc) { import_profile(profile_json({ "include-controls" => [ { "with-ids" => %w[zz-1] } ] }, modify: modify)) }

    def statement_ids(control) = Array(control["parts"]).find { |p| p["name"] == "statement" }["parts"].map { |p| p["id"] }

    it "stores the removes and the added parts, and keeps the priority where it was" do
      pc = doc.profile_controls.find_by(control_id: "zz-1")
      expect(pc.priority).to eq("P1")
      expect(pc.alters).to eq([ { "removes" => [ { "by-id" => "zz-1_smt.b" } ],
                                  "adds" => [ { "position" => "after", "by-id" => "zz-1_smt.a", "parts" => [ added ] } ] } ])
    end

    it "keeps every alter a profile writes for one control, in order" do
      second = { "control-id" => "zz-1", "removes" => [ { "by-name" => "guidance" } ] }
      twice = import_profile(profile_json({ "include-controls" => [ { "with-ids" => %w[zz-1] } ] },
                                          modify: { "alters" => modify["alters"] + [ second ] }))
      alters = twice.profile_controls.find_by(control_id: "zz-1").alters
      expect(alters.map { |a| a["removes"] }).to eq([ [ { "by-id" => "zz-1_smt.b" } ], [ { "by-name" => "guidance" } ] ])
      expect(twice.profile_controls.find_by(control_id: "zz-1").priority).to eq("P1")
    end

    it "the resolved catalog carries the added item and not the removed one" do
      resolved = JSON.parse(OscalResolvedProfileCatalogService.new(doc).export)
      control = resolved.dig("catalog", "groups").flat_map { |g| g["controls"] }.find { |c| c["id"] == "zz-1" }
      expect(statement_ids(control)).to eq(%w[zz-1_smt.a zz-1_smt.c])
    end

    it "the requirement text reads the same tailoring" do
      text = ControlRequirementText.for_profile(doc).for_control("zz-1")
      expect(text.parts.keys).to eq(%w[zz-1_smt.a zz-1_smt.c])
      expect(text.full).to include("Brief staff annually.")
      expect(text.full).not_to include("Review it.")
    end

    it "an SSP generated from the profile asks for the added item and not the removed one" do
      doc.update!(resolved_catalog_json: JSON.parse(OscalResolvedProfileCatalogService.new(doc).export),
                  lifecycle_status: "published")
      ssp = SspFromProfileService.new(doc, authorization_boundary: create(:authorization_boundary)).create
      ids = SspControlStatement.joins(:ssp_control).where(ssp_controls: { ssp_document_id: ssp.id }).pluck(:statement_id)
      expect(ids).to include("zz-1_smt.c")
      expect(ids).not_to include("zz-1_smt.b")
    end

    it "the profile export writes the alter back out" do
      exported = JSON.parse(OscalProfileExportService.new(doc).export)
      alter = exported.dig("profile", "modify", "alters").find { |a| a["control-id"] == "zz-1" }
      expect(alter["removes"]).to eq([ { "by-id" => "zz-1_smt.b" } ])
      expect(alter["adds"].flat_map { |a| Array(a["parts"]) }.map { |p| p["id"] }).to eq(%w[zz-1_smt.c])
      expect(alter["adds"].flat_map { |a| Array(a["props"]) }.map { |p| p["name"] }).to include("priority")
    end
  end

  describe "the same profile in JSON, YAML and XML" do
    let(:import) do
      { "include-all" => {},
        "exclude-controls" => [ { "matching" => [ { "pattern" => "zz-1?" } ] } ] }
    end
    let(:modify) { { "alters" => [ { "control-id" => "zz-2", "removes" => [ { "by-name" => "guidance" } ] } ] } }

    let(:xml) do
      <<~XML
        <profile xmlns="http://csrc.nist.gov/ns/oscal/1.0" uuid="#{SecureRandom.uuid}">
          <metadata><title>Agency ZZ Baseline</title><last-modified>2026-10-22T00:00:00Z</last-modified><version>1</version><oscal-version>1.2.3</oscal-version></metadata>
          <import href="#aaaaaaaa-0000-4000-8000-000000000001">
            <include-all/>
            <exclude-controls><matching pattern="zz-1?"/></exclude-controls>
          </import>
          <modify><alter control-id="zz-2"><remove by-name="guidance"/></alter></modify>
          <back-matter>
            <resource uuid="aaaaaaaa-0000-4000-8000-000000000001"><title>#{catalog_name}</title><rlink href="zz-catalog-#{catalog_uuid}.json"/></resource>
          </back-matter>
        </profile>
      XML
    end

    it "yields one selection and one set of alters" do
      data = profile_json(import, modify: modify)
      results = [ import_profile(data, format: "json"), import_profile(data, format: "yaml"), import_profile(xml, format: "xml") ]
                .map { |doc| doc.profile_controls.order(:row_order).pluck(:control_id, :alters) }

      expect(results.uniq.size).to eq(1)
      expect(results.first.map(&:first)).to eq(catalog_ids - [ "zz-10" ])
      expect(results.first.to_h["zz-2"]).to eq([ { "removes" => [ { "by-name" => "guidance" } ] } ])
    end
  end
end
