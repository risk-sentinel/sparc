# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "json"

# #1362 — the Sonar threshold: no new Sonar issues reach the target branch.
# Both directions: a new open issue breaches, a known or resolved one does not,
# and every unreadable input fails closed in report mode as well as enforce.
RSpec.describe "scripts/ci/sonar_new_issues.rb (#1362)" do
  script = Rails.root.join("scripts/ci/sonar_new_issues.rb").to_s

  around do |example|
    Dir.mktmpdir("sonar-threshold-spec-") { |dir| @dir = dir; example.run }
  end

  def write(name, content)
    path = File.join(@dir, name)
    File.write(path, content.is_a?(String) ? content : JSON.generate(content))
    path
  end

  LEGACY_STATUS = { "OPEN" => "OPEN", "FALSE_POSITIVE" => "RESOLVED", "ACCEPTED" => "RESOLVED", "FIXED" => "CLOSED" }.freeze

  # Shaped like hdf's raw file by default: only Sonar's legacy `status`, no
  # issueStatus or resolution (hdf's Issue type drops both). sonar_fields: true
  # adds issueStatus, as Sonar's own API returns it.
  def issue(key:, rule: "ruby:S1172", file: "app/models/a.rb", hash: "h-#{key}", status: "OPEN", sonar_fields: false)
    h = {
      "key" => key, "rule" => rule, "component" => "risk-sentinel_sparc:#{file}", "hash" => hash,
      "line" => 3, "message" => "m", "severity" => "MAJOR", "status" => LEGACY_STATUS.fetch(status)
    }
    h["issueStatus"] = status if sonar_fields
    h
  end

  def counts(open: 0, false_positive: 0, accepted: 0, fixed: 0)
    values = { "OPEN" => open, "FALSE_POSITIVE" => false_positive, "ACCEPTED" => accepted, "FIXED" => fixed }
    write("counts.json", { "facets" => [ { "property" => "issueStatuses",
                                           "values" => values.map { |k, v| { "val" => k, "count" => v } } } ] })
  end

  def raw(*issues)
    { "total" => issues.length, "p" => 1, "ps" => 500, "issues" => issues, "components" => [], "rules" => [] }
  end

  def threshold(mode: "enforce", max: 0)
    write("t-#{mode}-#{max}.yml", "mode: #{mode}\nnew_issues:\n  max: #{max}\n")
  end

  def run(script, base:, head:, threshold:, base_counts: nil)
    args = [ "--base", base, "--head", head, "--threshold", threshold ]
    args += [ "--base-counts", base_counts ] if base_counts
    Open3.capture2e("ruby", script, *args)
  end

  let(:base) { write("base.json", raw(issue(key: "A"), issue(key: "B", status: "FALSE_POSITIVE"))) }

  it "passes when every open PR issue is already on the target branch" do
    head = write("head.json", raw(issue(key: "A")))
    out, status = run(script, base: base, head: head, threshold: threshold)
    expect(status.exitstatus).to eq(0), out
    expect(out).to include("Sonar new-issue threshold: PASS (0 new")
  end

  it "fails in enforce mode when the PR adds an open issue the target branch does not have" do
    head = write("head.json", raw(issue(key: "A"), issue(key: "N", rule: "ruby:S9999", hash: "new")))
    out, status = run(script, base: base, head: head, threshold: threshold)
    expect(status.exitstatus).to eq(1), out
    expect(out).to include("1 new").and include("ruby:S9999")
  end

  it "reports the same breach without failing in report mode" do
    head = write("head.json", raw(issue(key: "N", rule: "ruby:S9999", hash: "new")))
    out, status = run(script, base: base, head: head, threshold: threshold(mode: "report"))
    expect(status.exitstatus).to eq(0), out
    expect(out).to include("BREACH (report mode, not blocking)")
  end

  it "allows new issues up to max" do
    head = write("head.json", raw(issue(key: "N", rule: "ruby:S9999", hash: "new")))
    out, status = run(script, base: base, head: head, threshold: threshold(max: 1))
    expect(status.exitstatus).to eq(0), out
  end

  it "matches by rule, file and hash when the PR issue has a different key (the issue moved)" do
    head = write("head.json", raw(issue(key: "OTHER-KEY", hash: "h-A")))
    out, status = run(script, base: base, head: head, threshold: threshold)
    expect(status.exitstatus).to eq(0), out
  end

  it "keeps a target-branch False positive: the same issue open in the PR is not new" do
    head = write("head.json", raw(issue(key: "PR-B", hash: "h-B")))
    out, status = run(script, base: base, head: head, threshold: threshold)
    expect(status.exitstatus).to eq(0), out
  end

  it "does not count PR issues resolved as False positive or Accepted (hdf raw shape: status only)" do
    head = write("head.json", raw(issue(key: "N1", hash: "n1", status: "FALSE_POSITIVE"),
                                  issue(key: "N2", hash: "n2", status: "ACCEPTED")))
    out, status = run(script, base: base, head: head, threshold: threshold)
    expect(status.exitstatus).to eq(0), out
  end

  it "reads issueStatus when the file carries it (Sonar's own API shape)" do
    head = write("head.json", raw(issue(key: "N1", hash: "n1", status: "FALSE_POSITIVE", sonar_fields: true),
                                  issue(key: "N2", hash: "n2", sonar_fields: true)))
    out, status = run(script, base: base, head: head, threshold: threshold)
    expect(status.exitstatus).to eq(1), out
    expect(out).to include("1 new")
  end

  it "reports exact resolution counts for trend tracking from the issueStatuses facet" do
    out, status = run(script, base: base, head: write("head.json", raw), threshold: threshold,
                              base_counts: counts(open: 402, false_positive: 3, accepted: 232, fixed: 71))
    expect(status.exitstatus).to eq(0), out
    expect(out).to match(/false positive \| 3 \|/).and match(/accepted \| 232 \|/)
      .and match(/fixed \| 71 \|/).and match(/Target branch: open \| 402 \|/)
  end

  it "without the facet file, says False positive and Accepted cannot be told apart" do
    out, = run(script, base: base, head: write("head.json", raw), threshold: threshold)
    expect(out).to match(/resolved, FP or accepted \(no counts file\) \| 1 \|/)
  end

  context "fails closed, in report mode too" do
    let(:report) { threshold(mode: "report") }

    it "on a missing head file" do
      out, status = run(script, base: base, head: File.join(@dir, "absent.json"), threshold: report)
      expect(status.exitstatus).to eq(2), out
    end

    it "on a file that is not JSON" do
      out, status = run(script, base: base, head: write("bad.json", "<html>"), threshold: report)
      expect(status.exitstatus).to eq(2), out
    end

    it "on a document without issues[]" do
      out, status = run(script, base: write("b.json", { "total" => 0 }), head: base, threshold: report)
      expect(status.exitstatus).to eq(2), out
    end

    it "on a truncated fetch (total disagrees with the issues held)" do
      short = raw(issue(key: "A")).merge("total" => 5)
      out, status = run(script, base: base, head: write("short.json", short), threshold: report)
      expect(status.exitstatus).to eq(2), out
      expect(out).to include("truncated")
    end

    it "on a counts file without the issueStatuses facet" do
      out, status = run(script, base: base, head: base, threshold: report, base_counts: write("c.json", { "facets" => [] }))
      expect(status.exitstatus).to eq(2), out
    end

    it "on an unknown threshold mode or key" do
      out, status = run(script, base: base, head: base, threshold: write("t.yml", "mode: warn\nnew_issues:\n  max: 0\n"))
      expect(status.exitstatus).to eq(2), out
      out, status = run(script, base: base, head: base, threshold: write("u.yml", "mode: report\nnew_issue:\n  max: 0\n"))
      expect(status.exitstatus).to eq(2), out
    end
  end

  it "ships in report mode with max 0 (the committed threshold)" do
    committed = YAML.safe_load(Rails.root.join("docs/compliance/sonar-threshold.yml").read)
    expect(committed).to eq("mode" => "report", "new_issues" => { "max" => 0 })
  end
end
