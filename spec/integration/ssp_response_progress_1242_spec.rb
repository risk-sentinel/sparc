# frozen_string_literal: true

require "rails_helper"
require "tempfile"

# #1242 — an SSP counts the responses its baseline requires, whoever published
# the baseline. No figure is pinned: each expectation is computed here from
# NIST's catalog file and the profile under test, by a walk written separately
# from the code under test. Agencies tailor; the count follows the profile.
RSpec.describe "SSP response counts follow the baseline (#1242)" do
  CATALOG_FILE = "NIST_SP-800-53_rev5_catalog.json"
  let(:dir) { Rails.root.join("spec/fixtures/files") }

  before(:all) do
    path = Rails.root.join("spec/fixtures/files/catalogs", CATALOG_FILE)
    @catalog = CatalogImportService.call(File.open(path), CATALOG_FILE)[:catalog]
    @catalog_json = JSON.parse(File.read(path))["catalog"]
  end

  after(:all) { @catalog&.destroy }

  # control id => the control's JSON, at any depth
  def catalog_controls
    @catalog_controls ||= begin
      walk = ->(node) { Array(node["controls"]).flat_map { |c| [ c ] + walk.call(c) } }
      Array(@catalog_json["groups"]).flat_map { walk.call(_1) }.index_by { _1["id"] }
    end
  end

  # The independent definition: statement parts with no statement part below
  # them, after the profile's removes and adds; one for a control with none.
  def expected_leaves(control_id, alters = [])
    control = JSON.parse(catalog_controls.fetch(control_id).to_json)
    statement = Array(control["parts"]).find { _1["name"] == "statement" }
    return [ "#{control_id}_smt" ] unless statement

    alters.select { _1["control-id"] == control_id }.each do |alter|
      ids = Array(alter["removes"]).filter_map { _1["by-id"] }
      prune = ->(part) { part["parts"] = Array(part["parts"]).reject { ids.include?(_1["id"]) }.each { prune.call(_1) } }
      prune.call(statement)
      Array(alter["adds"]).each do |add|
        target = find_part(statement, add["by-id"])
        (target["parts"] ||= []).concat(Array(add["parts"])) if target
      end
    end
    leaves = ->(part) do
      kids = Array(part["parts"]).select { %w[statement item].include?(_1["name"]) }
      kids.empty? ? [ part["id"] ] : kids.flat_map { leaves.call(_1) }
    end
    leaves.call(statement)
  end

  def find_part(part, id)
    return part if part["id"] == id

    Array(part["parts"]).each do |child|
      found = find_part(child, id)
      return found if found
    end
    nil
  end

  def selected_ids(profile_json)
    Array(profile_json["imports"]).flat_map do |imp|
      inc = Array(imp["include-controls"]).flat_map { Array(_1["with-ids"]) }
      exc = Array(imp["exclude-controls"]).flat_map { Array(_1["with-ids"]) }
      inc - exc
    end.uniq
  end

  def expected_required(profile_json)
    alters = Array(profile_json.dig("modify", "alters"))
    selected_ids(profile_json).sum { expected_leaves(_1, alters).size }
  end

  def import_profile(path, name)
    doc = create(:profile_document, status: "processing", file_type: "json", original_filename: name, control_catalog: nil)
    ProfileJsonParserService.new(doc, path.to_s).parse
    doc.reload
  end

  # Published as the end-to-end spec does: an SSP is made from a published profile.
  def ssp_for(profile)
    # The HIGH fixture's import names a back-matter resource the file does not
    # contain, so it links no catalog (see the #1252 selection spec); an
    # operator links it, as here.
    profile.update!(control_catalog: @catalog) unless profile.control_catalog
    profile.profile_controls.update_all(priority: "P1")
    resolved = JSON.parse(OscalResolvedProfileCatalogService.new(profile.reload).export)
    profile.update!(resolved_catalog_json: resolved, lifecycle_status: "published")
    SspFromProfileService.new(profile, authorization_boundary: create(:authorization_boundary)).create
  end

  %w[
    NIST_SP-800-53_rev5_LOW-baseline_profile.json
    NIST_SP-800-53_rev5_MODERATE-baseline_profile.json
    NIST_SP-800-53_rev5_HIGH-baseline_profile.json
    NIST_SP-800-53_rev5_MODERATE-tailored_profile.json
  ].each do |name|
    it "#{name}: requires one response per leaf part of each control the profile selects" do
      json = JSON.parse(File.read(dir.join("profiles", name)))["profile"]
      ssp = ssp_for(import_profile(dir.join("profiles", name), name))
      progress = SspResponseProgress.new(ssp)

      expect(progress.total.required).to eq(expected_required(json))
      # A new SSP has written nothing yet.
      expect(progress.total.owed).to eq(progress.total.required)
    end
  end

  describe "a tailored agency baseline (invented)" do
    let(:agency_json) do
      base = JSON.parse(File.read(dir.join("profiles", "NIST_SP-800-53_rev5_MODERATE-baseline_profile.json")))
      profile = base["profile"]
      profile["uuid"] = "6f1c2b0e-3a4d-4e5f-8a9b-0c1d2e3f4a5b"
      profile["metadata"]["title"] = "Invented agency tailored baseline"
      profile["imports"] = [ {
        "href" => profile["imports"].first["href"],
        # ac-2.11 is High-only; ac-2.2 is selected, then excluded.
        "include-controls" => [ { "with-ids" => %w[ac-1 ac-2 ac-2.1 ac-2.2 ac-2.11] } ],
        "exclude-controls" => [ { "with-ids" => %w[ac-2.2] } ]
      } ]
      profile["modify"] = { "alters" => [
        { "control-id" => "ac-1", "removes" => [ { "by-id" => "ac-1_smt.c" } ] },
        { "control-id" => "ac-2", "adds" => [ { "position" => "ending", "by-id" => "ac-2_smt",
                                                "parts" => [ { "id" => "ac-2_smt.agency-1", "name" => "item",
                                                               "prose" => "Invented agency requirement." } ] } ] }
      ] }
      profile.delete("merge")
      base
    end

    let(:profile) do
      file = Tempfile.new([ "agency-profile", ".json" ])
      file.write(agency_json.to_json)
      file.close
      import_profile(file.path, "agency-profile.json")
    end
    let(:ssp) { ssp_for(profile) }
    let(:alters) { agency_json["profile"]["modify"]["alters"] }

    it "follows the selection, the exclusion, the removed part and the added part" do
      expect(profile.profile_controls.pluck(:control_id)).to match_array(%w[ac-1 ac-2 ac-2.1 ac-2.11])

      progress = SspResponseProgress.new(ssp)
      expect(progress.total.required).to eq(expected_required(agency_json["profile"]))
      expect(progress.for_control("ac-1").required).to eq(expected_leaves("ac-1", alters).size)
      expect(progress.for_control("ac-1").required).to be < expected_leaves("ac-1").size
      expect(progress.for_control("ac-2").required).to eq(expected_leaves("ac-2").size + 1)
      expect(progress.for_control("ac-2.1").required).to eq(1)
      expect(progress.for_control("ac-2.2")).to be_nil
    end

    it "moves when a response is written, inherited, or cleared" do
      progress = -> { SspResponseProgress.new(ssp.reload).total }
      required = progress.call.required
      row = SspControlStatement.joins(:ssp_control).find_by(ssp_controls: { ssp_document_id: ssp.id }, statement_id: "ac-2.1_smt")

      expect(row.apply_author_edit("implementation_prose" => "Invented implementation.")).to be(true)
      expect(progress.call.done).to eq(1)

      provider = create(:ssp_control_statement, statement_id: "ac-2.1_smt", implementation_prose: "Provided.",
                                                set_parameters_data: [ { "tag" => "provided" } ])
      leaf = SspControlStatement.joins(:ssp_control)
                                .find_by(ssp_controls: { ssp_document_id: ssp.id }, statement_id: expected_leaves("ac-1", alters).first)
      create(:ssp_control_statement_inheritance, :from_ssp, ssp_control_statement: leaf, source: provider, source_uuid: provider.uuid)
      expect(progress.call.counts["inherited"]).to eq(1)
      expect(progress.call.done).to eq(2)

      row.apply_author_edit("implementation_prose" => "")
      expect(progress.call.done).to eq(1)
      expect(progress.call.required).to eq(required)
    end
  end
end
