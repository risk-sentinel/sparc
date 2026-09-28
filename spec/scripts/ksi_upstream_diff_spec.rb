# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "json"

# #1115 / #1172 — the drift tool compares FedRAMP/rules against the vendored
# snapshot. Specced against files only: no network.
RSpec.describe "bin/ksi_upstream_diff.rb" do
  let(:script) { Rails.root.join("bin/ksi_upstream_diff.rb").to_s }
  let(:vendored) { JSON.parse(Rails.root.join("lib/data/fedramp/fedramp-consolidated-rules.json").read) }

  around { |example| Dir.mktmpdir("ksi-diff-") { |dir| @dir = dir; example.run } }

  def run_against(upstream)
    path = File.join(@dir, "upstream.json")
    File.write(path, upstream.is_a?(String) ? upstream : JSON.generate(upstream))
    Open3.capture2e("ruby", script, "--upstream", path)
  end

  it "exits 0 when upstream matches the vendored snapshot" do
    out, status = run_against(vendored)

    expect(status.exitstatus).to eq(0), out
    expect(out).to include("No KSI drift")
  end

  it "exits 1 and names each change when upstream has moved on" do
    upstream = vendored.dup
    upstream["info"] = vendored["info"].merge("version" => "2026.10.01.01")
    iam = upstream["KSI"]["IAM"]["indicators"]
    iam.delete("KSI-IAM-JIT")
    iam["KSI-IAM-NEW"] = iam["KSI-IAM-ELP"].merge("name" => "A New One")
    iam["KSI-IAM-ELP"] = iam["KSI-IAM-ELP"].merge("controls" => iam["KSI-IAM-ELP"]["controls"] + [ "zz-99" ] - [ "ac-6" ])

    out, status = run_against(upstream)

    expect(status.exitstatus).to eq(1), out
    expect(out).to include("version: 2026.09.13.02 -> 2026.10.01.01")
    expect(out).to include("indicator removed: KSI-IAM-JIT")
    expect(out).to include("indicator added:   KSI-IAM-NEW A New One")
    expect(out).to match(/indicator changed: KSI-IAM-ELP — controls \+zz-99; controls -ac-6/)
  end

  it "reports a theme upstream removed" do
    upstream = vendored.merge("KSI" => vendored["KSI"].except("CED"))

    out, status = run_against(upstream)

    expect(status.exitstatus).to eq(1)
    expect(out).to include("theme removed: CED")
  end

  it "fails closed (exit 2) on a file that is not FedRAMP's rules" do
    out, status = run_against({ "hello" => "world" })

    expect(status.exitstatus).to eq(2)
    expect(out).to include("no KSI section")
  end

  it "fails closed (exit 2) on unparseable input" do
    _, status = run_against("{ not json")

    expect(status.exitstatus).to eq(2)
  end

  it "fails closed (exit 2) when the upstream file cannot be read" do
    _, status = Open3.capture2e("ruby", script, "--upstream", File.join(@dir, "missing.json"))

    expect(status.exitstatus).to eq(2)
  end
end
