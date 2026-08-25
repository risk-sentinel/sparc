# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "json"

# #1048 — a disposition must suppress its finding whichever identifier the
# scanner that found it happens to use.
#
# The register keys entries by `cve_id`. #1001 RE-KEYED several of them from a
# CVE to a GHSA id, because that is what grype reports, preserving the original
# in `also_known_as`. Nothing read `also_known_as`, so those dispositions
# matched grype's output and silently matched nothing from any CVE-keyed
# scanner.
#
# That was invisible for as long as the gate never ran. The moment the container
# is gated on trivy's SARIF — which keys by CVE — a re-keyed disposition would
# stop matching and a documented, approved finding would resurface as a new
# undispositioned one, red-lighting the build for no reason.
#
# Both directions are proved: the alias key IS emitted, and an entry without
# aliases does NOT gain spurious extra overrides.
RSpec.describe "HDF amendment identifier aliases (#1048)" do
  let(:amender) { Rails.root.join("bin/sparc_findings_to_hdf_amendments.rb").to_s }

  around do |example|
    Dir.mktmpdir("amend-alias-spec-") { |dir| @dir = dir; example.run }
  end

  def amend(yaml)
    input = File.join(@dir, "findings.yml")
    output = File.join(@dir, "amendments.json")
    File.write(input, yaml)
    stdout, status = Open3.capture2e(
      "ruby", amender, "--input", input, "--output", output, "--today", "2026-07-29"
    )
    raise "amender failed (#{status.exitstatus}): #{stdout}" unless status.success?

    JSON.parse(File.read(output)).fetch("overrides")
  end

  def finding(cve:, also_known_as: nil)
    # NOTE: `<<~` computes its strip width from the SOURCE lines and does not
    # re-indent interpolated text, so this must already carry the final
    # indentation (4 spaces — sibling of `cve_id`), not the source indentation.
    aka = also_known_as ? "\n    also_known_as: #{also_known_as}" : ""
    <<~YAML
      findings:
        - cve_id: #{cve}
          package: erb
          installed_version: "4.0.4"
          fixed_version: ">= 6.0.4"
          severity: HIGH
          disposition: deferred
          rationale: "Present on disk but shadowed; Bundler resolves a patched copy."
          nist_control: si-2
          reviewed_by: "@clem-field"
          discovery_date: '2026-07-29'
          next_review_date: '2026-08-28'#{aka}
    YAML
  end

  it "emits an override under the alias as well as the primary id" do
    overrides = amend(finding(cve: "GHSA-q339-8rmv-2mhv", also_known_as: "CVE-2026-41316"))
    ids = overrides.map { |o| o["requirementId"] }

    # grype reports the GHSA; trivy reports the CVE. Both must be suppressed.
    expect(ids).to contain_exactly("GHSA-q339-8rmv-2mhv", "CVE-2026-41316")
  end

  it "gives the alias override the same disposition as the primary" do
    overrides = amend(finding(cve: "GHSA-q339-8rmv-2mhv", also_known_as: "CVE-2026-41316"))

    primary = overrides.find { |o| o["requirementId"] == "GHSA-q339-8rmv-2mhv" }
    alias_o = overrides.find { |o| o["requirementId"] == "CVE-2026-41316" }

    # An alias that carried a weaker status would suppress under one scanner and
    # gate under another — worse than not aliasing at all.
    expect(alias_o.reject { |k, _| k == "requirementId" })
      .to eq(primary.reject { |k, _| k == "requirementId" })
  end

  it "emits exactly one override when there is no alias" do
    overrides = amend(finding(cve: "CVE-2026-0001"))

    expect(overrides.map { |o| o["requirementId"] }).to eq([ "CVE-2026-0001" ])
  end

  # Mutation guard: this is the assertion that fails if `finding_identifiers`
  # is reduced back to `[finding["cve_id"]]`.
  it "would fail if aliases were dropped again" do
    overrides = amend(finding(cve: "GHSA-g857-hhfv-j68w", also_known_as: "CVE-2026-27820"))

    expect(overrides.map { |o| o["requirementId"] }).to include("CVE-2026-27820")
  end
end
