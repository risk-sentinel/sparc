# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"

# #778 — the CI freshness gate for security-finding review dates. These specs
# prove BOTH directions against fixtures (a deliberately-stale one must fail),
# and that the committed sparc-findings.yml / .trivyignore are currently fresh.
RSpec.describe "scripts/ci/check_findings_freshness.rb (#778)" do
  script = Rails.root.join("scripts/ci/check_findings_freshness.rb").to_s

  # Run the script with a pinned "today" and optional file overrides.
  def run(script, findings: nil, trivyignore: nil, today: "2026-07-24", extra: {})
    env = { "FINDINGS_TODAY" => today }
    env["SPARC_FINDINGS_FILE"] = findings if findings
    env["SPARC_TRIVYIGNORE_FILE"] = trivyignore if trivyignore
    Open3.capture2e(env.merge(extra), "ruby", script)
  end

  around do |example|
    Dir.mktmpdir("findings-spec-") { |dir| @dir = dir; example.run }
  end

  def write(name, content)
    path = File.join(@dir, name)
    File.write(path, content)
    path
  end

  # An empty trivyignore keeps the fixture findings tests from also reading the
  # real .trivyignore.
  let(:empty_trivyignore) { write(".trivyignore", "# no ignores\n") }

  it "passes when a finding's next_review_date is in the future" do
    findings = write("f.yml", <<~YAML)
      findings:
        - cve_id: CVE-2026-0001
          disposition: accepted
          next_review_date: "2026-12-01"
    YAML
    out, status = run(script, findings: findings, trivyignore: empty_trivyignore)
    expect(status).to be_success, out
    expect(out).to match(/fresh/i)
  end

  it "FAILS when a finding's next_review_date is in the past" do
    findings = write("f.yml", <<~YAML)
      findings:
        - cve_id: CVE-2026-0002
          disposition: accepted
          next_review_date: "2026-01-01"
    YAML
    out, status = run(script, findings: findings, trivyignore: empty_trivyignore)
    expect(status).not_to be_success
    expect(out).to match(/overdue/i)
    expect(out).to include("CVE-2026-0002")
  end

  it "exempts false_positive dispositions even with a past date" do
    findings = write("f.yml", <<~YAML)
      findings:
        - cve_id: CVE-2026-0003
          disposition: false_positive
          next_review_date: "2026-01-01"
    YAML
    _out, status = run(script, findings: findings, trivyignore: empty_trivyignore)
    expect(status).to be_success
  end

  it "flags an unparseable next_review_date" do
    findings = write("f.yml", <<~YAML)
      findings:
        - cve_id: CVE-2026-0004
          disposition: accepted
          next_review_date: "not-a-date"
    YAML
    out, status = run(script, findings: findings, trivyignore: empty_trivyignore)
    expect(status).not_to be_success
    expect(out).to match(/unparseable/i)
  end

  it "FAILS on a stale .trivyignore review date (> 90 days)" do
    fresh_findings = write("f.yml", "findings: []\n")
    trivy = write(".trivyignore", "CVE-2020-0001\n# Reviewed: 2026-01-01\n")
    out, status = run(script, findings: fresh_findings, trivyignore: trivy)
    expect(status).not_to be_success
    expect(out).to match(/Reviewed/i)
  end

  it "passes a recently-reviewed .trivyignore" do
    fresh_findings = write("f.yml", "findings: []\n")
    trivy = write(".trivyignore", "CVE-2020-0001\n# Reviewed: 2026-07-20\n")
    _out, status = run(script, findings: fresh_findings, trivyignore: trivy)
    expect(status).to be_success
  end

  # ── Retire-with-evidence (owner-decided 2026-08-20) ─────────────────────
  #
  # `remediated` is not exempted from the cadence — it is removed from the
  # active file entirely, and removal requires proof. The v1.12.2 audit (#770)
  # found eleven entries claiming remediation while the package was still in
  # the image; verifying this bundle's file found TWENTY more, all of them
  # Debian-era claims carried across the UBI9 migration without re-checking.
  # Exempting the disposition would have made every one of those permanent.
  def empty_retired = write("retired.yml", "findings: []\n")

  it "FAILS when a remediated finding is still in the active file" do
    findings = write("f.yml", <<~YAML)
      findings:
        - cve_id: CVE-2026-0010
          disposition: remediated
          next_review_date: "2099-01-01"
    YAML
    out, status = run(script, findings: findings, trivyignore: empty_trivyignore,
                      extra: { "SPARC_FINDINGS_RETIRED_FILE" => empty_retired })

    expect(status).not_to be_success, out
    expect(out).to include("CVE-2026-0010")
    # A future review date must NOT rescue it — the point is that the cadence is
    # the wrong question, not that the date is stale.
    expect(out).to match(/RETIRED, not reviewed/i)
  end

  it "passes once that finding is retired WITH proof of absence" do
    findings = write("f.yml", "findings: []\n")
    retired  = write("retired.yml", <<~YAML)
      findings:
        - cve_id: CVE-2026-0010
          disposition: remediated
          verified_absent_on: "2026-08-20"
          verified_by: "grype 0.114.0 (image scan)"
    YAML
    out, status = run(script, findings: findings, trivyignore: empty_trivyignore,
                      extra: { "SPARC_FINDINGS_RETIRED_FILE" => retired })

    expect(status).to be_success, out
  end

  # Retirement has to be harder than review, or it is just a delete key.
  it "FAILS when a retired finding carries no proof of absence" do
    findings = write("f.yml", "findings: []\n")
    retired  = write("retired.yml", <<~YAML)
      findings:
        - cve_id: CVE-2026-0011
          disposition: remediated
    YAML
    out, status = run(script, findings: findings, trivyignore: empty_trivyignore,
                      extra: { "SPARC_FINDINGS_RETIRED_FILE" => retired })

    expect(status).not_to be_success, out
    expect(out).to include("CVE-2026-0011")
    expect(out).to match(/verified_absent_on/)
    expect(out).to match(/without evidence is deletion/i)
  end

  it "still gates the review date on a LIVE disposition" do
    findings = write("f.yml", <<~YAML)
      findings:
        - cve_id: CVE-2026-0012
          disposition: deferred
          next_review_date: "2026-01-01"
    YAML
    out, status = run(script, findings: findings, trivyignore: empty_trivyignore,
                      extra: { "SPARC_FINDINGS_RETIRED_FILE" => empty_retired })

    expect(status).not_to be_success, out
    expect(out).to match(/overdue/i)
  end

  it "the committed sparc-findings.yml + .trivyignore are currently fresh" do
    # Pinned to a date on/after which every committed next_review_date is still
    # in the future and the .trivyignore review is recent — a canary that CI
    # would have caught the drift #770 found.
    out, status = run(script, today: "2026-07-24")
    expect(status).to be_success, out
  end
end
