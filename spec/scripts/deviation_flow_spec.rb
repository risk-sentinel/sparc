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

  # Deviations from BOTH the active and retired registers. Retirement moves a
  # finding out of the active file, so a check reading only the active file
  # silently narrows every time something is remediated.
  def committed_deviations
    %w[sparc-findings.yml sparc-findings.retired.yml].flat_map do |name|
      register = YAML.safe_load_file(
        Rails.root.join("docs/compliance", name), permitted_classes: [ Date ], aliases: true
      )
      Array(register["findings"]).filter_map { |f| f["deviation"] }
    end
  end

  describe "the committed register" do
    it "validates, and every deviation carries a type and mitigating factors" do
      out = File.join(@dir, "real.json")
      stdout, status = Open3.capture2e(
        "ruby", amender,
        "--input", Rails.root.join("docs/compliance/sparc-findings.yml").to_s,
        "--output", out, "--today", "2026-07-30"
      )

      expect(status.exitstatus).to eq(0), stdout

      register = YAML.safe_load_file(
        Rails.root.join("docs/compliance/sparc-findings.yml"), permitted_classes: [ Date ], aliases: true
      )
      # BOTH registers. A deviation is the approval for accepting a risk that
      # EXISTS, so once a finding is remediated it retires and takes its deviation
      # with it — as all three did on 2026-08-29, leaving the active register with
      # none. Reading only the active file would make the loop below vacuous
      # exactly when everything has been fixed, which is the moment it is least
      # obvious that the check stopped checking.
      deviations = committed_deviations
      expect(deviations).not_to be_empty,
        "no deviation in either register — the machinery is unexercised, so the " \
        "validation below would assert nothing"
      deviations.each do |dev|
        expect(%w[false_positive risk_adjustment operational_requirement]).to include(dev["type"])
        expect(%w[deviation-requested deviation-approved]).to include(dev["risk_status"])
        next unless dev["type"] == "risk_adjustment"
        expect(Array(dev["mitigating_factors"])).not_to be_empty
      end
    end

    it "never claims an approval without naming approver, PR and date" do
      # Also both registers, and for the same reason: retiring a finding must not
      # be a way for an approved deviation to escape this check. This example has
      # no non-empty guard of its own, so against the active file alone it would
      # now pass by having nothing left to look at.
      approved = committed_deviations.select { |d| d["risk_status"] == "deviation-approved" }
      expect(approved).not_to be_empty, "no approved deviation in either register to check"

      approved.each do |dev|
        %w[approved_by approved_in approved_at].each do |field|
          expect(dev[field].to_s.strip).not_to be_empty,
            "a deviation-approved finding has no #{field}: #{dev.inspect}"
        end
      end
    end
  end

  describe "the approval loop (#865)" do
    # A stubbed `gh` on PATH, not a cleared PATH — clearing PATH would break
    # `ruby` itself and the example would pass for the wrong reason.
    def stub_gh(permission: "admin", approver: "clem-field")
      bin = File.join(@dir, "bin")
      FileUtils.mkdir_p(bin)
      File.write(File.join(bin, "gh"), <<~SH)
        #!/bin/sh
        case "$*" in
          *"collaborators/#{approver}/permission"*) echo '{"permission":"#{permission}"}' ;;
          *"collaborators/"*"/permission"*)         echo '{"permission":"write"}' ;;
          *"--json latestReviews"*)                 echo '{"latestReviews":[{"state":"APPROVED","author":{"login":"#{approver}"}}]}' ;;
          *) echo '{}' ;;
        esac
      SH
      FileUtils.chmod(0o755, File.join(bin, "gh"))
      "#{bin}:#{ENV['PATH']}"
    end

    def requested_register
      write("f.yml", finding(deviation: risk_adjustment(status: "deviation-requested", approval: false)))
    end

    def run_gate(path, env = {})
      Open3.capture2e(
        { "SPARC_FINDINGS_FILE" => path, "GITHUB_EVENT_NAME" => "pull_request",
          "SPARC_PR_NUMBER" => "999", "SPARC_BASE_REF" => "refs/none" }.merge(env),
        "ruby", approver_script
      )
    end

    let(:approver_script) { Rails.root.join("scripts/ci/check_deviation_approvals.rb").to_s }
    let(:applier)         { Rails.root.join("scripts/ci/apply_deviation_approval.rb").to_s }

    it "blocks while a deviation is still awaiting approval" do
      stdout, status = run_gate(requested_register, "PATH" => stub_gh)

      expect(status.exitstatus).to eq(1), stdout
      expect(stdout).to include("DEVIATION AWAITING APPROVAL")
    end

    it "refuses to record an approval from a reviewer without admin rights" do
      path = requested_register
      stdout, status = Open3.capture2e(
        { "SPARC_FINDINGS_FILE" => path, "SPARC_REVIEW_STATE" => "APPROVED",
          "SPARC_REVIEWER" => "someuser", "SPARC_PR_NUMBER" => "999",
          "PATH" => stub_gh(approver: "clem-field") },
        "ruby", applier
      )

      expect(status.exitstatus).to eq(1), stdout
      expect(stdout).to include("may only be approved by admin or maintain")
      expect(File.read(path)).to include("deviation-requested")
    end

    it "ignores a review that is not an approval" do
      path = requested_register
      before = File.read(path)
      stdout, status = Open3.capture2e(
        { "SPARC_FINDINGS_FILE" => path, "SPARC_REVIEW_STATE" => "COMMENTED",
          "SPARC_REVIEWER" => "clem-field", "SPARC_PR_NUMBER" => "999",
          "PATH" => stub_gh },
        "ruby", applier
      )

      expect(status.exitstatus).to eq(0), stdout
      expect(File.read(path)).to eq(before)
    end

    it "records an admin approval and then passes the gate" do
      path = requested_register
      _out, status = Open3.capture2e(
        { "SPARC_FINDINGS_FILE" => path, "SPARC_REVIEW_STATE" => "APPROVED",
          "SPARC_REVIEWER" => "clem-field", "SPARC_REVIEWED_AT" => "2026-07-30T12:00:00Z",
          "SPARC_PR_NUMBER" => "999", "PATH" => stub_gh },
        "ruby", applier
      )
      expect(status.exitstatus).to eq(0)

      body = File.read(path)
      expect(body).to include("deviation-approved")
      expect(body).to include('approved_by: "@clem-field"')
      expect(body).to include('approved_at: "2026-07-30"')

      stdout, gate = run_gate(path, "PATH" => stub_gh, "GITHUB_EVENT_NAME" => "pull_request_review")
      expect(gate.exitstatus).to eq(0), stdout
      expect(stdout).to include("corroborated")
    end

    it "rejects a hand-typed approval from someone who never reviewed" do
      path = requested_register
      Open3.capture2e(
        { "SPARC_FINDINGS_FILE" => path, "SPARC_REVIEW_STATE" => "APPROVED",
          "SPARC_REVIEWER" => "clem-field", "SPARC_PR_NUMBER" => "999", "PATH" => stub_gh },
        "ruby", applier
      )
      forged = File.join(@dir, "forged.yml")
      File.write(forged, File.read(path).gsub("@clem-field", "@mallory"))

      stdout, status = run_gate(forged, "PATH" => stub_gh)

      expect(status.exitstatus).to eq(1), stdout
      expect(stdout).to include("NOT CORROBORATED")
      expect(stdout).to include("has not submitted an approving review")
    end
  end
end
