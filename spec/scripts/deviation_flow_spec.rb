# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "fileutils"
require "json"

# #865 — the FedRAMP deviation flow.
#
# Two properties matter and both are proved in BOTH directions:
#
#   1. The deviation's risk_status, not the disposition, decides whether a
#      finding gates the build. deviation-approved -> notApplicable (suppressed
#      from the threshold residual); deviation-requested -> failed (a CRITICAL
#      then breaches threshold.yml's failed.critical.max: 0). If this ever
#      inverts, an unapproved deviation on a CVSS 10.0 goes green silently.
#
#   2. A deviation cannot approve itself. The approval is the code-owner review
#      on the PR, so the CI gate must fail when no approving review exists.
RSpec.describe "FedRAMP deviation flow (#865)" do
  # `let`, not local variables: a `def` below opens a new scope and cannot see
  # locals assigned here, while it can call a `let`-defined instance method.
  let(:amender)  { Rails.root.join("bin/sparc_findings_to_hdf_amendments.rb").to_s }
  let(:approver) { Rails.root.join("scripts/ci/check_deviation_approvals.rb").to_s }

  around do |example|
    Dir.mktmpdir("deviation-spec-") { |dir| @dir = dir; example.run }
  end

  def write(name, content)
    path = File.join(@dir, name)
    File.write(path, content)
    path
  end

  def amend(findings_path)
    out = File.join(@dir, "amendments.json")
    stdout, status = Open3.capture2e(
      "ruby", amender, "--input", findings_path, "--output", out, "--today", "2026-07-29"
    )
    overrides =
      if File.exist?(out)
        parsed = JSON.parse(File.read(out))
        parsed.values.find { |v| v.is_a?(Array) && v.first.is_a?(Hash) } || []
      else
        []
      end
    [ status.exitstatus, stdout, overrides ]
  end

  def finding(cve: "CVE-2026-0001", severity: "CRITICAL", disposition: "deferred", deviation: nil)
    <<~YAML
      findings:
        - cve_id: #{cve}
          package: sqlite-libs
          installed_version: "3.34.1-9.el9_7"
          fixed_version: "none"
          severity: #{severity}
          disposition: #{disposition}
          rationale: "Test fixture."
          nist_control: si-2
          reviewed_by: "@clem-field"
          discovery_date: "2026-07-29"
          next_review_date: "2026-08-28"
      #{deviation}
    YAML
  end

  def risk_adjustment(status: "deviation-approved", factors: true, approval: true)
    lines = []
    lines << "    deviation:"
    lines << "      type: risk_adjustment"
    lines << "      risk_status: #{status}"
    lines << "      adjusted_severity: LOW"
    if factors
      lines << "      mitigating_factors:"
      lines << "        - description: \"ruby is not linked against libsqlite3\""
    end
    if approval
      lines << "      approved_by: \"@risk-sentinel/sparc-admin\""
      lines << "      approved_in: \"risk-sentinel/sparc#863\""
      lines << "      approved_at: \"2026-07-29\""
    end
    lines.join("\n")
  end

  describe "risk_status drives the gating status" do
    it "suppresses an APPROVED deviation as notApplicable" do
      code, _out, overrides = amend(write("f.yml", finding(deviation: risk_adjustment)))

      expect(code).to eq(0)
      expect(overrides.map { |o| o["status"] }).to eq([ "notApplicable" ])
    end

    it "keeps an UNAPPROVED deviation as failed so a CRITICAL still gates" do
      code, _out, overrides = amend(
        write("f.yml", finding(deviation: risk_adjustment(status: "deviation-requested", approval: false)))
      )

      expect(code).to eq(0)
      expect(overrides.map { |o| o["status"] }).to eq([ "failed" ]),
        "an unapproved deviation must remain `failed` — otherwise it is suppressed before anyone approves it"
    end

    it "carries the mitigating factors into the override reason" do
      _code, _out, overrides = amend(write("f.yml", finding(deviation: risk_adjustment)))

      expect(overrides.first["reason"]).to include("risk_adjustment", "deviation-approved")
      expect(overrides.first["reason"]).to include("not linked against libsqlite3")
    end
  end

  describe "validation" do
    it "rejects a risk_adjustment with no mitigating factors" do
      code, out, _ = amend(write("f.yml", finding(deviation: risk_adjustment(factors: false))))

      expect(code).to eq(2)
      expect(out).to include("requires at least one mitigating_factors entry")
    end

    it "rejects an approved deviation that names no approver" do
      code, out, _ = amend(write("f.yml", finding(deviation: risk_adjustment(approval: false))))

      expect(code).to eq(2)
      expect(out).to include("requires approved_by")
    end

    it "rejects a CRITICAL deferred finding with no deviation at all" do
      code, out, _ = amend(write("f.yml", finding(deviation: nil)))

      expect(code).to eq(2)
      expect(out).to include("CRITICAL deferred findings require a deviation block")
    end

    it "rejects an unknown deviation type" do
      dev = risk_adjustment.sub("risk_adjustment", "made_up_type")
      code, out, _ = amend(write("f.yml", finding(deviation: dev)))

      expect(code).to eq(2)
      expect(out).to include("deviation.type must be one of")
    end

    it "rejects a false_positive deviation that claims mitigations" do
      dev = risk_adjustment.sub("type: risk_adjustment", "type: false_positive")
      code, out, _ = amend(write("f.yml", finding(deviation: dev)))

      expect(code).to eq(2)
      expect(out).to include("must not carry mitigating_factors")
    end

    it "rejects a deviation attached to a non-deferred disposition" do
      code, out, _ = amend(
        write("f.yml", finding(severity: "HIGH", disposition: "accepted", deviation: risk_adjustment))
      )

      expect(code).to eq(2)
      expect(out).to include("only valid on disposition=deferred")
    end
  end

  describe "the committed register" do
    it "validates and emits no failed overrides (every deviation is approved)" do
      out = File.join(@dir, "real.json")
      stdout, status = Open3.capture2e(
        "ruby", amender,
        "--input", Rails.root.join("docs/compliance/sparc-findings.yml").to_s,
        "--output", out, "--today", "2026-07-29"
      )

      expect(status.exitstatus).to eq(0), stdout
      overrides = JSON.parse(File.read(out)).values.find { |v| v.is_a?(Array) && v.first.is_a?(Hash) } || []
      expect(overrides.map { |o| o["status"] }.uniq).to eq([ "notApplicable" ])
    end
  end

  describe "scripts/ci/check_deviation_approvals.rb" do
    it "passes when the change introduces no newly-approved deviation" do
      findings = write("f.yml", finding(severity: "HIGH", disposition: "accepted", deviation: nil))
      stdout, status = Open3.capture2e(
        { "SPARC_FINDINGS_FILE" => findings, "GITHUB_EVENT_NAME" => "pull_request" },
        "ruby", approver
      )

      expect(status.exitstatus).to eq(0), stdout
      expect(stdout).to include("No newly-approved deviations")
    end

    # Stub `gh` on PATH rather than clearing PATH — clearing it would break
    # `ruby` itself and the example would pass for the wrong reason.
    def stub_gh(body)
      bin = File.join(@dir, "bin")
      FileUtils.mkdir_p(bin)
      File.write(File.join(bin, "gh"), "#!/bin/sh\ncat <<'JSON'\n#{body}\nJSON\n")
      FileUtils.chmod(0o755, File.join(bin, "gh"))
      "#{bin}:#{ENV['PATH']}"
    end

    it "fails a pull request that self-approves a deviation with no review" do
      findings = write("f.yml", finding(deviation: risk_adjustment))
      stdout, status = Open3.capture2e(
        {
          "SPARC_FINDINGS_FILE" => findings,
          "GITHUB_EVENT_NAME"   => "pull_request",
          "SPARC_PR_NUMBER"     => "999999",
          "SPARC_BASE_REF"      => "refs/nonexistent",
          "PATH"                => stub_gh('{"reviewDecision":"REVIEW_REQUIRED","latestReviews":[]}')
        },
        "ruby", approver
      )

      expect(status.exitstatus).to eq(1), stdout
      expect(stdout).to include("DEVIATION NOT APPROVED")
    end

    it "passes once the PR carries an approving code-owner review" do
      findings = write("f.yml", finding(deviation: risk_adjustment))
      stdout, status = Open3.capture2e(
        {
          "SPARC_FINDINGS_FILE" => findings,
          "GITHUB_EVENT_NAME"   => "pull_request_review",
          "SPARC_PR_NUMBER"     => "999999",
          "SPARC_BASE_REF"      => "refs/nonexistent",
          "PATH"                => stub_gh(
            '{"reviewDecision":"APPROVED","latestReviews":[{"state":"APPROVED","author":{"login":"clem-field"}}]}'
          )
        },
        "ruby", approver
      )

      expect(status.exitstatus).to eq(0), stdout
      expect(stdout).to include("Deviation approval satisfied")
    end

    it "does not gate on push events — branch protection covers those" do
      findings = write("f.yml", finding(deviation: risk_adjustment))
      stdout, status = Open3.capture2e(
        {
          "SPARC_FINDINGS_FILE" => findings,
          "GITHUB_EVENT_NAME"   => "push",
          "SPARC_BASE_REF"      => "refs/nonexistent"
        },
        "ruby", approver
      )

      expect(status.exitstatus).to eq(0), stdout
      expect(stdout).to include("branch protection")
    end
  end
end
