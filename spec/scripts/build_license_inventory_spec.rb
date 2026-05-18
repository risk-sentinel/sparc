require "rails_helper"
require Rails.root.join("scripts/ci/build_license_inventory.rb")

RSpec.describe LicenseInventoryBuilder do
  let(:policy) do
    {
      "enforce" => false,
      "allowlist" => [ "MIT", "Apache-2.0", "BSD-3-Clause" ],
      "warn_list" => [ "GPL-3.0", "AGPL-3.0" ],
      "blocklist" => [ "BUSL-1.1", "SSPL-1.0" ],
      "unmapped_action" => "warn",
      "skip_patterns" => [ "^\\./.*" ]
    }
  end

  let(:dispositions) { [] }

  def sbom(*components)
    {
      "bomFormat" => "CycloneDX",
      "specVersion" => "1.6",
      "components" => components
    }
  end

  def write_sbom(path, *components)
    File.write(path, sbom(*components).to_json)
    path
  end

  def component(name, version: "1.0.0", license_id: nil, license_name: nil, expression: nil)
    licenses =
      if license_id
        [ { "license" => { "id" => license_id, "url" => "https://opensource.org/licenses/#{license_id}" } } ]
      elsif license_name
        [ { "license" => { "name" => license_name } } ]
      elsif expression
        [ { "expression" => expression } ]
      end

    base = { "name" => name, "version" => version, "type" => "library", "purl" => "pkg:gem/#{name}@#{version}" }
    base["licenses"] = licenses if licenses
    base
  end

  around(:each) do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      example.run
    end
  end

  describe "#build" do
    it "tallies summary stats correctly" do
      path = write_sbom("#{@tmpdir}/ruby.json",
        component("a", license_id: "MIT"),
        component("b", license_id: "Apache-2.0"),
        component("c")) # no license
      report = described_class.new(sboms: { ruby: path }, policy: policy, dispositions: dispositions).build

      expect(report[:summary]).to include(
        total_components: 3,
        with_licenses: 2,
        without_licenses: 1,
        coverage_pct: 66.67,
        unique_licenses: 2
      )
    end

    it "groups by license sorted by count desc with disposition labels" do
      path = write_sbom("#{@tmpdir}/ruby.json",
        component("a", license_id: "MIT"),
        component("b", license_id: "MIT"),
        component("c", license_id: "GPL-3.0"),
        component("d", license_id: "BUSL-1.1"))
      report = described_class.new(sboms: { ruby: path }, policy: policy, dispositions: dispositions).build

      keys = report[:by_license].keys
      expect(keys.first).to eq("MIT")
      expect(report[:by_license]["MIT"][:disposition]).to eq("OK")
      expect(report[:by_license]["GPL-3.0"][:disposition]).to eq("WARN")
      expect(report[:by_license]["BUSL-1.1"][:disposition]).to eq("BLOCK")
    end

    it "extracts ids from CycloneDX license-shape variants" do
      path = write_sbom("#{@tmpdir}/ruby.json",
        component("a", license_id: "MIT"),
        component("b", license_name: "MIT-ish"),
        component("c", expression: "MIT OR Apache-2.0"))
      report = described_class.new(sboms: { ruby: path }, policy: policy, dispositions: dispositions).build

      licenses = report[:by_component].map { |r| r[:license] }
      expect(licenses).to contain_exactly("MIT", "MIT-ish", "MIT")
      # Expression should split into both -- second license is in all_licenses
      expression_row = report[:by_component].find { |r| r[:name] == "c" }
      expect(expression_row[:all_licenses]).to contain_exactly("MIT", "Apache-2.0")
    end

    it "skips components matching policy skip_patterns" do
      path = write_sbom("#{@tmpdir}/ruby.json",
        component("./vendored/thing", license_id: nil),
        component("real-gem", license_id: "MIT"))
      report = described_class.new(sboms: { ruby: path }, policy: policy, dispositions: dispositions).build

      action_items_names = report[:action_items].map { |a| a[:name] }
      expect(action_items_names).not_to include("./vendored/thing")
    end

    it "generates action items for unmapped components per unmapped_action" do
      path = write_sbom("#{@tmpdir}/ruby.json", component("nameless"))
      report = described_class.new(sboms: { ruby: path }, policy: policy, dispositions: dispositions).build

      expect(report[:action_items].length).to eq(1)
      expect(report[:action_items].first).to include(severity: :unmapped, reason: a_string_including("No license"))
    end

    it "treats unknown licenses (not in any list) as warn" do
      path = write_sbom("#{@tmpdir}/ruby.json", component("a", license_id: "Some-Unknown-License-1.0"))
      report = described_class.new(sboms: { ruby: path }, policy: policy, dispositions: dispositions).build

      ai = report[:action_items].first
      expect(ai[:severity]).to eq(:warn)
      expect(ai[:reason]).to match(/not on allowlist/i)
    end

    it "respects per-component dispositions (accepted suppresses action item)" do
      path = write_sbom("#{@tmpdir}/ruby.json", component("gpl-gem", license_id: "GPL-3.0"))
      disp = [ { "name" => "gpl-gem", "disposition" => "accepted", "rationale" => "..." } ]
      report = described_class.new(sboms: { ruby: path }, policy: policy, dispositions: disp).build

      expect(report[:action_items]).to be_empty
      row = report[:by_component].first
      expect(row[:disposition]).to eq("accepted")
    end

    it "treats `replace` disposition as a remaining action item until resolved" do
      path = write_sbom("#{@tmpdir}/ruby.json", component("busl-gem", license_id: "BUSL-1.1"))
      disp = [ { "name" => "busl-gem", "disposition" => "replace", "target_component" => "fork-gem" } ]
      report = described_class.new(sboms: { ruby: path }, policy: policy, dispositions: disp).build

      ai = report[:action_items].first
      expect(ai[:severity]).to eq(:warn)
      expect(ai[:reason]).to match(/Replace pending.*fork-gem/)
    end

    it "version-specific dispositions only match the listed version" do
      path = write_sbom("#{@tmpdir}/ruby.json",
        component("v-gem", version: "1.0.0", license_id: "AGPL-3.0"),
        component("v-gem", version: "2.0.0", license_id: "AGPL-3.0"))
      disp = [ { "name" => "v-gem", "version" => "1.0.0", "disposition" => "accepted", "rationale" => "1.x only" } ]
      report = described_class.new(sboms: { ruby: path }, policy: policy, dispositions: disp).build

      # v1 should be accepted, v2 still triggers warn.
      v1 = report[:by_component].find { |r| r[:version] == "1.0.0" }
      v2 = report[:by_component].find { |r| r[:version] == "2.0.0" }
      expect(v1[:disposition]).to eq("accepted")
      expect(v2[:severity]).to eq(:warn)
    end

    it "tracks source SBOM on each component row" do
      ruby = write_sbom("#{@tmpdir}/ruby.json", component("gem-a", license_id: "MIT"))
      fs   = write_sbom("#{@tmpdir}/trivy-fs.json", component("os-pkg", license_id: "Apache-2.0"))
      report = described_class.new(sboms: { ruby: ruby, "trivy-fs": fs }, policy: policy, dispositions: dispositions).build

      sources = report[:by_component].map { |r| [ r[:name], r[:source] ] }
      expect(sources).to contain_exactly([ "gem-a", "ruby" ], [ "os-pkg", "trivy-fs" ])
    end
  end

  describe "#to_markdown" do
    it "produces a human-readable report with action item table when items exist" do
      path = write_sbom("#{@tmpdir}/ruby.json",
        component("clean", license_id: "MIT"),
        component("gpl", license_id: "GPL-3.0"))
      builder = described_class.new(sboms: { ruby: path }, policy: policy, dispositions: dispositions)
      md = builder.to_markdown(builder.build)

      expect(md).to include("# SPARC License Inventory")
      expect(md).to include("## Summary")
      expect(md).to include("## License Distribution")
      expect(md).to include("## Action Items")
      expect(md).to include("`gpl`")
      expect(md).to include("`GPL-3.0`")
    end

    it "emits a no-action-items message when policy is clean" do
      path = write_sbom("#{@tmpdir}/ruby.json", component("a", license_id: "MIT"))
      builder = described_class.new(sboms: { ruby: path }, policy: policy, dispositions: dispositions)
      md = builder.to_markdown(builder.build)

      expect(md).to include("No action items needed".sub("needed", "")).or include("None")
    end
  end

  # Issue #472 — merged-SBOM output
  describe "#merged_sbom" do
    it "produces a valid CycloneDX 1.6 document with all components" do
      ruby = write_sbom("#{@tmpdir}/ruby.json",
        component("gem-a", license_id: "MIT"),
        component("gem-b", license_id: "Apache-2.0"))
      builder = described_class.new(sboms: { ruby: ruby }, policy: policy, dispositions: dispositions)
      builder.build
      merged = builder.merged_sbom

      expect(merged["bomFormat"]).to eq("CycloneDX")
      expect(merged["specVersion"]).to eq("1.6")
      expect(merged["components"].length).to eq(2)
      expect(merged.dig("metadata", "tools").first["name"]).to eq("sparc/build_license_inventory.rb")
    end

    it "deduplicates components by purl across multiple SBOMs" do
      ruby = write_sbom("#{@tmpdir}/ruby.json",
        component("nokogiri", version: "1.19.3", license_id: "MIT"))
      trivy_container = write_sbom("#{@tmpdir}/container.json",
        component("nokogiri", version: "1.19.3", license_id: "MIT"))
      builder = described_class.new(
        sboms: { ruby: ruby, "trivy-container": trivy_container },
        policy: policy, dispositions: dispositions
      )
      builder.build
      merged = builder.merged_sbom

      # One row (deduplicated), with source SBOMs listed
      expect(merged["components"].length).to eq(1)
      source_prop = merged["components"].first["properties"].find { |p| p["name"] == "sparc:source-sboms" }
      sources = source_prop["value"].split(",")
      expect(sources).to contain_exactly("ruby", "trivy-container")
    end

    it "treats different versions of the same gem as distinct components" do
      ruby = write_sbom("#{@tmpdir}/ruby.json",
        component("rails", version: "8.1.2", license_id: "MIT"),
        component("rails", version: "8.1.3", license_id: "MIT"))
      builder = described_class.new(sboms: { ruby: ruby }, policy: policy, dispositions: dispositions)
      builder.build
      merged = builder.merged_sbom

      expect(merged["components"].length).to eq(2)
      versions = merged["components"].map { |c| c["version"] }
      expect(versions).to contain_exactly("8.1.2", "8.1.3")
    end

    it "uses name+version+type as fallback dedup key when purl is missing" do
      sbom1 = {
        "bomFormat" => "CycloneDX",
        "components" => [
          { "name" => "no-purl-gem", "version" => "1.0.0", "type" => "library" }
        ]
      }
      sbom2 = {
        "bomFormat" => "CycloneDX",
        "components" => [
          { "name" => "no-purl-gem", "version" => "1.0.0", "type" => "library" }
        ]
      }
      File.write("#{@tmpdir}/a.json", sbom1.to_json)
      File.write("#{@tmpdir}/b.json", sbom2.to_json)

      builder = described_class.new(
        sboms: { a: "#{@tmpdir}/a.json", b: "#{@tmpdir}/b.json" },
        policy: policy, dispositions: dispositions
      )
      builder.build
      expect(builder.merged_sbom["components"].length).to eq(1)
    end

    it "records git_sha in the metadata properties" do
      ruby = write_sbom("#{@tmpdir}/ruby.json", component("a", license_id: "MIT"))
      builder = described_class.new(sboms: { ruby: ruby }, policy: policy, dispositions: dispositions, git_sha: "deadbeef")
      builder.build

      sha_prop = builder.merged_sbom.dig("metadata", "properties").find { |p| p["name"] == "sparc:git-sha" }
      expect(sha_prop["value"]).to eq("deadbeef")
    end
  end
end
