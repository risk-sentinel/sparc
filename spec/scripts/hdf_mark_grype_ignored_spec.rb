# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"

# #1368 — hdf-cli 3.8.0 no longer reads impact 0 as notApplicable, so the
# grype matches an ignore rule suppressed came out `failed`. The script marks
# exactly those results `skipped`, which 3.8.0 translates to notApplicable.
RSpec.describe "bin/hdf_mark_grype_ignored.rb" do
  let(:script) { Rails.root.join("bin/hdf_mark_grype_ignored.rb").to_s }

  around { |example| Dir.mktmpdir("grype-ignored-") { |dir| @dir = dir; example.run } }

  def control(id, impact:, status: "failed")
    { "id" => id, "impact" => impact, "tags" => { "severity" => "High" },
      "results" => [ { "status" => status, "code_desc" => "match", "message" => "artifact" } ] }
  end

  def run_on(controls)
    path = File.join(@dir, "grype.hdf.json")
    File.write(path, JSON.pretty_generate("profiles" => [ { "name" => "Anchore - Grype", "controls" => controls } ]))
    out, status = Open3.capture2e("ruby", script, "--input", path)
    expect(status).to be_success, out
    [ JSON.parse(File.read(path))["profiles"][0]["controls"], out, path ]
  end

  it "marks an ignored match skipped, with the reason" do
    controls, out, = run_on([ control("Grype-Ignored-Match/CVE-2026-1", impact: 0) ])

    expect(controls[0]["results"][0]).to include("status" => "skipped")
    expect(controls[0]["results"][0]["skip_message"]).to include("grype ignore rule")
    expect(out).to include("1 ignored-match result(s)")
  end

  it "leaves a real match failed" do
    controls, = run_on([ control("Grype/CVE-2026-2", impact: 0.7) ])

    expect(controls[0]["results"][0]["status"]).to eq("failed")
  end

  it "leaves a document with no ignored matches byte-identical" do
    path = File.join(@dir, "grype.hdf.json")
    raw = JSON.generate("profiles" => [ { "controls" => [ control("Grype/CVE-2026-3", impact: 0.5) ] } ])
    File.write(path, raw)
    _, status = Open3.capture2e("ruby", script, "--input", path)

    expect(status).to be_success
    expect(File.read(path)).to eq(raw)
  end

  it "is idempotent" do
    _, _, path = run_on([ control("Grype-Ignored-Match/CVE-2026-4", impact: 0) ])
    first = File.read(path)
    out, = Open3.capture2e("ruby", script, "--input", path)

    expect(File.read(path)).to eq(first)
    expect(out).to include("0 ignored-match result(s)")
  end
end
