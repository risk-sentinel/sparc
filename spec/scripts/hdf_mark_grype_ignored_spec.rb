# frozen_string_literal: true

require "rails_helper"
require "open3"
require "stringio"
require "tmpdir"
load Rails.root.join("bin/hdf_mark_grype_ignored.rb").to_s

# #1368 — hdf-cli 3.8.0 no longer reads impact 0 as notApplicable, so the
# grype matches an ignore rule suppressed came out `failed`. The script marks
# exactly those results `skipped`, which 3.8.0 translates to notApplicable.
#
# In-process through HdfMarkGrypeIgnored, plus one run of the real command line.
RSpec.describe "bin/hdf_mark_grype_ignored.rb" do
  around { |example| Dir.mktmpdir("grype-ignored-") { |dir| @dir = dir; example.run } }

  def control(id, impact:, status: "failed")
    { "id" => id, "impact" => impact, "tags" => { "severity" => "High" },
      "results" => [ { "status" => status, "code_desc" => "match", "message" => "artifact" } ] }
  end

  def write(controls)
    File.join(@dir, "grype.hdf.json").tap do |path|
      File.write(path, JSON.pretty_generate("profiles" => [ { "name" => "Anchore - Grype", "controls" => controls } ]))
    end
  end

  def controls_in(path)
    JSON.parse(File.read(path))["profiles"][0]["controls"]
  end

  it "marks an ignored match skipped, with the reason" do
    path = write([ control("Grype-Ignored-Match/CVE-2026-1", impact: 0) ])

    expect(HdfMarkGrypeIgnored.run(input: path)).to eq(1)
    result = controls_in(path)[0]["results"][0]
    expect(result["status"]).to eq("skipped")
    expect(result["skip_message"]).to include("grype ignore rule")
  end

  it "leaves a real match failed" do
    path = write([ control("Grype/CVE-2026-2", impact: 0.7) ])

    expect(HdfMarkGrypeIgnored.run(input: path)).to eq(0)
    expect(controls_in(path)[0]["results"][0]["status"]).to eq("failed")
  end

  it "leaves a document with no ignored matches byte-identical" do
    path = File.join(@dir, "grype.hdf.json")
    raw = JSON.generate("profiles" => [ { "controls" => [ control("Grype/CVE-2026-3", impact: 0.5) ] } ])
    File.write(path, raw)

    HdfMarkGrypeIgnored.run(input: path)
    expect(File.read(path)).to eq(raw)
  end

  it "is idempotent" do
    path = write([ control("Grype-Ignored-Match/CVE-2026-4", impact: 0) ])
    HdfMarkGrypeIgnored.run(input: path)
    first = File.read(path)

    expect(HdfMarkGrypeIgnored.run(input: path)).to eq(0)
    expect(File.read(path)).to eq(first)
  end

  it "writes to --output and leaves the input alone" do
    path = write([ control("Grype-Ignored-Match/CVE-2026-5", impact: 0) ])
    before = File.read(path)
    out_path = File.join(@dir, "out.json")
    out = StringIO.new

    expect(HdfMarkGrypeIgnored.main([ "--input", path, "--output", out_path ], out: out)).to eq(0)
    expect(File.read(path)).to eq(before)
    expect(controls_in(out_path)[0]["results"][0]["status"]).to eq("skipped")
    expect(out.string).to include("1 ignored-match result(s)")
  end

  it "refuses to run without --input" do
    err = StringIO.new

    expect(HdfMarkGrypeIgnored.main([], err: err)).to eq(2)
    expect(err.string).to include("--input is required")
  end

  it "runs as the command security.yml calls" do
    path = write([ control("Grype-Ignored-Match/CVE-2026-6", impact: 0) ])
    out, status = Open3.capture2e("ruby", Rails.root.join("bin/hdf_mark_grype_ignored.rb").to_s, "--input", path)

    expect(status).to be_success, out
    expect(controls_in(path)[0]["results"][0]["status"]).to eq("skipped")
  end
end
