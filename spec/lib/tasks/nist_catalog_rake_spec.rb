require "rails_helper"
require "rake"
require "tmpdir"

# #1228 — the tasks that build the bundled Rev 5 catalog, check a catalog file,
# and record NIST's releases. Writes go to a temporary directory, never the
# committed files, and `gh` is stubbed, so nothing here touches the network.
RSpec.describe "lib/tasks/nist_catalog.rake", type: :task do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  let(:dir) { Pathname(Dir.mktmpdir) }

  after { FileUtils.rm_rf(dir) }

  def run(name, *args)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*args)
  end

  describe "catalog:build_rev5" do
    it "writes exactly the committed JSON from the vendored XML" do
      allow(NistCatalogSource).to receive(:json_path).and_return(dir.join("out.json"))

      expect { run("catalog:build_rev5") }.to output(/wrote .*out\.json .*OscalCatalogXmlToJson #{Regexp.escape(OscalCatalogXmlToJson::VERSION)}/).to_stdout
      expect(dir.join("out.json").read).to eq(Rails.root.join(NistCatalogSource::DIR, NistCatalogSource::JSON_FILE).read)
    end

    it "refuses an XML file that is not the one the provenance records" do
      dir.join("other.xml").write("<catalog/>")
      allow(NistCatalogSource).to receive(:xml_path).and_return(dir.join("other.xml"))
      allow(NistCatalogSource).to receive(:json_path).and_return(dir.join("out.json"))

      expect { run("catalog:build_rev5") }.to raise_error(SystemExit).and output(/not the file the provenance records/).to_stderr
      expect(dir.join("out.json")).not_to exist
    end

    it "refuses an XML file the schema rejects" do
      allow(OscalSchemaValidationService).to receive(:validate_xml)
        .and_return(OscalSchemaValidationService::Result.new(valid?: false, errors: [ "invented error" ], schema_version: "1.2.3"))
      allow(NistCatalogSource).to receive(:json_path).and_return(dir.join("out.json"))

      expect { run("catalog:build_rev5") }.to raise_error(SystemExit).and output(/not schema-valid: invented error/).to_stderr
      expect(dir.join("out.json")).not_to exist
    end
  end

  describe "catalog:integrity" do
    let(:fixtures) { Rails.root.join("spec/fixtures/files/catalogs") }

    it "checks the bundled catalog by default" do
      expect { run("catalog:integrity") }
        .to output(/\A#{Regexp.escape(NistCatalogSource.json_path.to_s)}: \d+ finding\(s\)/).to_stdout
    end

    it "reads an XML, a YAML or a JSON catalog by its extension, and lists each finding" do
      allow(CatalogIntegrityService).to receive(:check).and_call_original
      allow(CatalogIntegrityService).to receive(:check)
        .with(satisfy { |c| c.dig("catalog", "uuid").present? }).and_return([ "invented finding" ])

      %w[xml yaml json].each do |ext|
        path = fixtures.join("invented-values-catalog.#{ext}")
        expect { run("catalog:integrity", path.to_s) }.to output("#{path}: 1 finding(s)\n  invented finding\n").to_stdout
      end
      expect(CatalogIntegrityService).to have_received(:check).exactly(3).times
    end
  end

  describe "catalog:check_nist_release" do
    let(:commit) { NistCatalogSource.source_commit }
    let(:ok) { instance_double(Process::Status, success?: true) }

    def stub_gh(responses)
      allow(Open3).to receive(:capture3) do |*argv|
        path = argv.last
        body = responses.find { |pattern, _| path.include?(pattern) }&.last
        raise "unexpected gh call: #{path}" unless body

        [ JSON.generate(body), "", ok ]
      end
    end

    before { allow(NistCatalogSource).to receive(:release_data_path).and_return(dir.join("releases.json")) }

    it "records each release and says none carries the commit yet" do
      stub_gh("commits/" => { "commit" => { "committer" => { "date" => "2026-10-22T00:00:00Z" } } },
              "releases?" => [ { "tag_name" => "v9.0.0", "published_at" => "2026-01-01T00:00:00Z" } ],
              "compare/" => { "status" => "ahead" })

      expect { run("catalog:check_nist_release") }.to output(/no release carries #{commit[0, 8]} yet/).to_stdout

      record = JSON.parse(dir.join("releases.json").read)
      expect(record).to include("repository" => "usnistgov/oscal-content", "fix_commit" => commit,
                                 "fix_commit_date" => "2026-10-22T00:00:00Z")
      expect(record["releases"]).to eq([ { "tag" => "v9.0.0", "published_at" => "2026-01-01T00:00:00Z",
                                            "contains_fix_commit" => false } ])
    end

    it "names a release whose tree already has the commit" do
      stub_gh("commits/" => { "commit" => { "committer" => { "date" => "2026-10-22T00:00:00Z" } } },
              "releases?" => [ { "tag_name" => "v9.1.0", "published_at" => "2026-11-01T00:00:00Z" } ],
              "compare/" => { "status" => "behind" })

      expect { run("catalog:check_nist_release") }
        .to output(/NIST release v9\.1\.0 carries #{commit[0, 8]}: replace the pre-release catalog/).to_stdout
      expect(JSON.parse(dir.join("releases.json").read)["releases"].first["contains_fix_commit"]).to be(true)
    end

    it "stops, writing nothing, when gh fails" do
      allow(Open3).to receive(:capture3)
        .and_return([ "", "invented: not logged in\n", instance_double(Process::Status, success?: false) ])

      expect { run("catalog:check_nist_release") }
        .to raise_error(SystemExit).and output(/gh api .* failed: invented: not logged in/).to_stderr
      expect(dir.join("releases.json")).not_to exist
    end
  end
end
