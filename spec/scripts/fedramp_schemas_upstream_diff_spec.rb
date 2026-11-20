# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "json"

# #1354 — the drift tool compares FedRAMP's published schemas with the
# vendored copies. Specced against a directory only: no network.
RSpec.describe "bin/fedramp_schemas_upstream_diff.rb" do
  let(:script) { Rails.root.join("bin/fedramp_schemas_upstream_diff.rb").to_s }
  let(:vendored_dir) { Rails.root.join("lib/data/fedramp/schemas") }

  around do |example|
    Dir.mktmpdir("fedramp-schemas-diff-") do |dir|
      @dir = dir
      FileUtils.cp(Dir[vendored_dir.join("*.json")], dir)
      example.run
    end
  end

  def run_tool = Open3.capture2e("ruby", script, "--dir", @dir)

  it "exits 0 when upstream matches the vendored schemas, even minified" do
    file = File.join(@dir, "fedramp-incident-report-schema-2026-06-24.json")
    File.write(file, JSON.generate(JSON.parse(File.read(file))))

    out, status = run_tool
    expect(status.exitstatus).to eq(0), out
    expect(out).to include("No FedRAMP schema drift")
  end

  it "exits 1 and names a changed schema with its versions" do
    file = File.join(@dir, "fedramp-incident-report-schema-2026-06-24.json")
    doc = JSON.parse(File.read(file))
    old_version = doc["$schemaVersion"]
    File.write(file, JSON.generate(doc.merge("$schemaVersion" => "9.9.9")))

    out, status = run_tool
    expect(status.exitstatus).to eq(1), out
    expect(out).to include("CHANGED  fedramp-incident-report-schema-2026-06-24.json: " \
                           "$schemaVersion #{old_version.inspect} -> \"9.9.9\"")
  end

  it "reports a schema upstream added and one it removed" do
    File.write(File.join(@dir, "fedramp-new-report-schema-2026-06-24.json"), JSON.generate("$schemaVersion" => "0.1.0"))
    File.delete(File.join(@dir, "fedramp-advisor-information-schema-2026-06-24.json"))

    out, status = run_tool
    expect(status.exitstatus).to eq(1), out
    expect(out).to include("ADDED    fedramp-new-report-schema-2026-06-24.json")
    expect(out).to include("REMOVED  fedramp-advisor-information-schema-2026-06-24.json")
  end

  it "fails closed when the comparison cannot happen" do
    File.write(File.join(@dir, "fedramp-incident-report-schema-2026-06-24.json"), "{ not json")

    out, status = run_tool
    expect(status.exitstatus).to eq(2), out
    expect(out).to include("is not JSON")
  end
end
