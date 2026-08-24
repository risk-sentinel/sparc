# frozen_string_literal: true

require "rails_helper"
require "open3"
require "json"

# #987 — a Brakeman ignore entry is keyed by a FINGERPRINT that hashes the code
# it describes, so editing a line near an ignored warning moves the fingerprint
# and silently un-ignores it. There is no signal for that, and the SAST step is
# `continue-on-error`, so nothing failed.
#
# It has bitten twice, in opposite directions:
#
#   1. #947 changed an attestation permit list from `:attester_name,
#      :attester_email` to `:attester_user_id`. The fingerprint moved, two
#      long-standing ignore entries stopped matching, and their Mass Assignment
#      warnings resurfaced. CI stayed green throughout; it was found by hand.
#
#   2. The other half of the same event left DEAD entries behind — notes still
#      claiming `Attestation#role` was "descriptive metadata ... NOT an
#      app-level authorization" and citing `Attestation::ROLES`, after #947 had
#      made the role roster-validated and deleted ROLES. Re-ignoring under that
#      note would have carried a false security rationale forward.
#
# A dead entry is worse than a missing one: it reads as a reviewed, justified
# decision while describing code that no longer exists. This makes both
# directions visible.
RSpec.describe "config/brakeman.ignore drift (#987)" do
  # ~7s locally. Run once for the whole file rather than per example.
  before(:all) do
    stdout, status = Open3.capture2e(
      "bundle", "exec", "brakeman", "--no-pager", "-f", "json", "-q",
      chdir: Rails.root.to_s
    )
    # Brakeman exits non-zero on warnings by design in some configs; parse
    # regardless and let the assertions speak.
    json = stdout[/\{.*\}/m]
    raise "brakeman produced no JSON (status #{status.exitstatus}):\n#{stdout[0, 2000]}" unless json

    @report = JSON.parse(json)
  end

  let(:config_path) { Rails.root.join("config/brakeman.ignore") }
  let(:configured) { JSON.parse(File.read(config_path)).fetch("ignored_warnings") }
  let(:matched) { @report.fetch("ignored_warnings", []).map { |w| w["fingerprint"] } }

  it "has no ignore entry that matches nothing (a note outliving its code)" do
    dead = configured.reject { |e| matched.include?(e["fingerprint"]) }

    detail = dead.map { |e| "  #{e['fingerprint']}\n    #{e['note'].to_s[0, 200]}" }.join("\n")

    expect(dead).to be_empty, <<~MSG
      #{dead.size} entry/entries in config/brakeman.ignore match no current Brakeman warning.

      Either the code they describe is gone — delete the entry — or its
      fingerprint moved because the code changed, in which case RE-READ the note
      before re-adding it. A note that survives the code it justified is how a
      false security rationale gets carried forward (#987).

      #{detail}
    MSG
  end

  it "reports no unignored warnings" do
    warnings = @report.fetch("warnings", [])
    detail = warnings.map { |w| "  #{w['warning_type']} #{w['file']}:#{w['line']} — #{w['message']}" }.join("\n")

    # The gate that blocks a merge is security_gate's brakeman band, which reads
    # the SARIF with suppressions filtered out (#1048). This asserts the same
    # posture at development time, where the fix is cheap.
    expect(warnings).to be_empty, "Brakeman reported #{warnings.size} unignored warning(s):\n#{detail}"
  end
end
