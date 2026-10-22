# frozen_string_literal: true

# #1228 — the bundled NIST SP 800-53 Rev 5 catalog: build it, check it, and
# notice when NIST releases what it currently takes from `develop`.
#
#   bin/rails catalog:build_rev5               — regenerate the committed JSON from the vendored XML
#   bin/rails catalog:integrity[path]          — run the content checks over a catalog file
#   bin/rails catalog:check_nist_release       — ask GitHub whether a NIST release carries the fixes
require "open3"

namespace :catalog do
  desc "Regenerate lib/data/catalogs/NIST_SP-800-53_rev5_catalog.json from the vendored NIST XML"
  task build_rev5: :environment do
    xml = NistCatalogSource.xml_path.read
    recorded = NistCatalogSource.provenance.dig("files", NistCatalogSource::XML, "sha256")
    actual = Digest::SHA256.hexdigest(xml)
    abort "The vendored XML (#{actual}) is not the file the provenance records (#{recorded})." unless actual == recorded

    validation = OscalSchemaValidationService.validate_xml(:catalog, xml, version: OscalSchema::DEFAULT_VERSION)
    abort "The vendored XML is not schema-valid: #{validation.errors.first(5).join('; ')}" unless validation.valid?

    NistCatalogSource.build!
    puts "  wrote #{NistCatalogSource.json_path.relative_path_from(Rails.root)} " \
         "(#{NistCatalogSource.json_path.size} bytes, OscalCatalogXmlToJson #{OscalCatalogXmlToJson::VERSION})"
  end

  desc "Run the catalog integrity checks over an OSCAL catalog file (default: the bundled Rev 5)"
  task :integrity, [ :path ] => :environment do |_t, args|
    path = Pathname(args[:path].presence || NistCatalogSource.json_path)
    content = path.read
    catalog = case path.extname.downcase
    when ".xml"          then OscalCatalogXmlToJson.convert(content)
    when ".yaml", ".yml" then YAML.safe_load(content, permitted_classes: [ Date, Time ])
    else JSON.parse(content)
    end

    findings = CatalogIntegrityService.check(catalog)
    puts "#{path}: #{findings.size} finding(s)"
    findings.each { |finding| puts "  #{finding}" }
  end

  # Network task, never run by the suite: the suite reads what this records.
  desc "Record whether a usnistgov/oscal-content release carries the pinned develop fixes (needs gh)"
  task check_nist_release: :environment do
    repo = "usnistgov/oscal-content"
    commit = NistCatalogSource.source_commit
    gh = lambda do |path|
      out, err, status = Open3.capture3("gh", "api", path)
      abort "gh api #{path} failed: #{err.strip}" unless status.success?
      JSON.parse(out)
    end

    commit_date = gh.call("repos/#{repo}/commits/#{commit}").dig("commit", "committer", "date")
    releases = gh.call("repos/#{repo}/releases?per_page=20").map do |release|
      tag = release["tag_name"]
      # `behind` or `identical`: the release's tree already has the commit.
      status = gh.call("repos/#{repo}/compare/#{tag}...#{commit}")["status"]
      { "tag" => tag, "published_at" => release["published_at"],
        "contains_fix_commit" => %w[behind identical].include?(status) }
    end

    record = {
      "description" => "Recorded by bin/rails catalog:check_nist_release (#1228). " \
                       "spec/lib/nist_catalog_source_spec.rb reads it; the suite never calls the network.",
      "recorded_at" => Time.current.utc.iso8601,
      "repository" => repo,
      "fix_commit" => commit,
      "fix_commit_date" => commit_date,
      "releases" => releases
    }
    path = NistCatalogSource.release_data_path
    path.write("#{JSON.pretty_generate(record)}\n")

    carrying = NistCatalogSource.releases_requiring_action(record)
    puts "  recorded #{releases.size} release(s) in #{path.relative_path_from(Rails.root)}"
    if carrying.any?
      puts "  NIST release #{carrying.map { |r| r['tag'] }.join(', ')} carries #{commit[0, 8]}: " \
           "replace the pre-release catalog and set pre_release to false."
    else
      puts "  no release carries #{commit[0, 8]} yet; the catalog stays pre-release."
    end
  end
end
