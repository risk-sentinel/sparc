# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "json"

# #1186 — a CodeQL disposition covers the results it names, and no others.
#
# Both directions, because each is a different way for a waiver to lie: a NEW
# result under a dispositioned rule would otherwise be suppressed unreviewed,
# and a VANISHED one leaves a pin vouching for code that no longer exists.
RSpec.describe "bin/codeql_pin_check.rb" do
  let(:script) { Rails.root.join("bin/codeql_pin_check.rb").to_s }
  let(:rule) { "rb/csrf-protection-disabled" }

  around { |example| Dir.mktmpdir("pin-check-") { |dir| @dir = dir; example.run } }

  def result(path, hash)
    { "ruleId" => rule, "partialFingerprints" => { "primaryLocationLineHash" => hash },
      "locations" => [ { "physicalLocation" => { "artifactLocation" => { "uri" => path } } } ] }
  end

  def write(name, content)
    File.join(@dir, name).tap { |p| File.write(p, content.is_a?(String) ? content : JSON.generate(content)) }
  end

  def run(results:, pins:, hdf_count: results.size, disposition: "false_positive", incremental: nil)
    run_props = incremental ? { "properties" => { "incrementalMode" => incremental } } : {}
    sarif = write("codeql.sarif", "runs" => [ { "results" => results }.merge(run_props) ])
    hdf = write("codeql.hdf.json", "profiles" => [ { "controls" => [
      { "id" => rule, "results" => Array.new(hdf_count) { { "status" => "failed" } } }
    ] } ])
    register = write("findings.yml", YAML.dump("findings" => [
      { "cve_id" => rule, "disposition" => disposition,
        "pinned_results" => pins.map { |path, hash| { "path" => path, "line_hash" => hash } } }
    ]))
    out, status = Open3.capture2e("ruby", script, "--register", register, "--sarif", sarif, "--hdf", hdf)
    [ out, status ]
  end

  it "passes when the live results are exactly the pinned ones" do
    out, status = run(results: [ result("a.rb", "h1:1"), result("b.rb", "h2:1") ],
                      pins: [ [ "a.rb", "h1:1" ], [ "b.rb", "h2:1" ] ])

    expect(status).to be_success, out
    expect(out).to include("exact match")
  end

  it "FAILS on a new, unpinned result — the rule-level waiver this exists to prevent" do
    out, status = run(results: [ result("a.rb", "h1:1"), result("new.rb", "h9:1") ], pins: [ [ "a.rb", "h1:1" ] ])

    expect(status).not_to be_success
    expect(out).to match(/UNDISPOSITIONED result at new\.rb \(h9:1\)/)
  end

  it "FAILS on a pin with no live result — an edited line changes its hash, which is when a re-review is due" do
    out, status = run(results: [ result("a.rb", "h1-edited:1") ], pins: [ [ "a.rb", "h1:1" ] ])

    expect(status).not_to be_success
    expect(out).to match(/STALE pin a\.rb \(h1:1\)/)
    expect(out).to match(/UNDISPOSITIONED result at a\.rb \(h1-edited:1\)/)
  end

  # PR #1188: pull requests run DIFF-INFORMED analysis, so a data-flow rule
  # reports only results inside the changed lines. An absent pin is then
  # expected, and failing on it would red-light every PR that does not touch
  # a pinned line.
  describe "a diff-informed (pull request) scan" do
    it "reports an absent pin as a notice, not a failure" do
      out, status = run(results: [], pins: [ [ "a.rb", "h1:1" ] ], incremental: "diff-informed,overlay")

      expect(status).to be_success, out
      expect(out).to match(/outside this diff-informed scan/)
    end

    it "still FAILS on a new, unpinned result — anything it reports is inside the diff" do
      out, status = run(results: [ result("new.rb", "h9:1") ], pins: [ [ "a.rb", "h1:1" ] ], incremental: "diff-informed")

      expect(status).not_to be_success
      expect(out).to match(/UNDISPOSITIONED result at new\.rb/)
    end

    it "treats a non-diff incremental mode (overlay alone) as a FULL scan" do
      _out, status = run(results: [], pins: [ [ "a.rb", "h1:1" ] ], incremental: "overlay")

      expect(status).not_to be_success
    end
  end

  it "FAILS when the HDF and the SARIF disagree on the count — the pins must describe the assessed document" do
    out, status = run(results: [ result("a.rb", "h1:1") ], pins: [ [ "a.rb", "h1:1" ] ], hdf_count: 2)

    expect(status).not_to be_success
    expect(out).to match(/HDF holds 2 result\(s\) but the SARIF 1/)
  end

  it "ignores a remediated entry's pins" do
    _out, status = run(results: [], pins: [ [ "a.rb", "h1:1" ] ], hdf_count: 0, disposition: "remediated")

    expect(status).to be_success
  end

  it "fails CLOSED when an input is missing, rather than passing on nothing" do
    register = write("findings.yml", YAML.dump("findings" => []))
    out, status = Open3.capture2e("ruby", script, "--register", register, "--sarif", File.join(@dir, "absent.sarif"),
                                  "--hdf", File.join(@dir, "absent.json"))

    expect(status).not_to be_success
    expect(out).to match(/failing closed/)
  end

  describe "results with no fingerprint" do
    def run_with(extra)
      sarif = write("codeql.sarif", "runs" => [ { "results" => [ result("a.rb", "h1:1"), extra ] } ])
      hdf = write("codeql.hdf.json", "profiles" => [ { "controls" => [ { "id" => rule, "results" => [ {} ] } ] } ])
      register = write("findings.yml", YAML.dump("findings" => [
        { "cve_id" => rule, "disposition" => "false_positive", "pinned_results" => [ { "path" => "a.rb", "line_hash" => "h1:1" } ] }
      ]))
      Open3.capture2e("ruby", script, "--register", register, "--sarif", sarif, "--hdf", hdf)
    end

    it "ignores them in a rule the register does not pin" do
      out, status = run_with("ruleId" => "rb/unrelated", "locations" => [])

      expect(status).to be_success, out
    end

    it "fails closed on them in a PINNED rule" do
      out, status = run_with("ruleId" => rule, "locations" => [])

      expect(status).not_to be_success
      expect(out).to match(/has no location or line hash/)
    end
  end

  it "reads the v3 HDF shape (baselines/requirements) as well as v2" do
    sarif = write("codeql.sarif", "runs" => [ { "results" => [ result("a.rb", "h1:1") ] } ])
    hdf = write("codeql.hdf.json", "baselines" => [ { "requirements" => [ { "id" => rule, "results" => [ {} ] } ] } ])
    register = write("findings.yml", YAML.dump("findings" => [
      { "cve_id" => rule, "disposition" => "false_positive", "pinned_results" => [ { "path" => "a.rb", "line_hash" => "h1:1" } ] }
    ]))

    out, status = Open3.capture2e("ruby", script, "--register", register, "--sarif", sarif, "--hdf", hdf)
    expect(status).to be_success, out
  end

  describe "the converter's side of the rule" do
    let(:amender) { Rails.root.join("bin/sparc_findings_to_hdf_amendments.rb").to_s }

    def amend(entry)
      input = write("register.yml", YAML.dump("findings" => [ {
        "severity" => "HIGH", "disposition" => "false_positive", "rationale" => "measured",
        "reviewed_by" => "@reviewer", "discovery_date" => "2026-09-24", "next_review_date" => "2026-10-24"
      }.merge(entry) ]))
      Open3.capture2e("ruby", amender, "--input", input, "--output", File.join(@dir, "out.json"), "--today", "2026-09-27")
    end

    it "refuses a scanner-RULE entry with no pins — it would waive every instance of the rule" do
      out, status = amend("cve_id" => rule)

      expect(status).not_to be_success
      expect(out).to match(/rb\/csrf-protection-disabled: a scanner-RULE disposition must carry pinned_results/)
    end

    it "accepts a pinned rule entry" do
      out, status = amend("cve_id" => rule, "pinned_results" => [ { "path" => "a.rb", "line_hash" => "h1:1" } ])

      expect(status).to be_success, out
    end

    it "refuses a pin missing its hash" do
      out, status = amend("cve_id" => rule, "pinned_results" => [ { "path" => "a.rb" } ])

      expect(status).not_to be_success
      expect(out).to match(/pinned_results\[0\] needs both path and line_hash/)
    end

    it "does not demand pins of an advisory id" do
      _out, status = amend("cve_id" => "CVE-2026-0001")

      expect(status).to be_success
    end

    # PR #1188 review: pins are required only where the pin check enforces
    # them (CodeQL), and a distro advisory is an advisory, not a rule.
    it "does not treat a distro advisory id as a scanner rule" do
      out, status = amend("cve_id" => "RHSA-2026:1234")

      expect(status).to be_success, out
    end

    it "refuses a rule id from a scanner no pin check covers, pinned or not" do
      out, status = amend("cve_id" => "BRAKE0105", "pinned_results" => [ { "path" => "a.rb", "line_hash" => "h1:1" } ])

      expect(status).not_to be_success
      expect(out).to match(/BRAKE0105: not an advisory id and not a CodeQL rule id/)
    end
  end
end
