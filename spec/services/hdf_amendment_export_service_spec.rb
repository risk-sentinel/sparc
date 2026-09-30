# frozen_string_literal: true

require "rails_helper"

RSpec.describe HdfAmendmentExportService do
  let(:boundary) { create(:authorization_boundary) }
  let(:scan_run) { create(:scan_run, authorization_boundary: boundary) }
  let(:runner)   { instance_double(HdfRunner, amend_verify: true) }
  let(:service)  { described_class.new(boundary, runner: runner) }

  # A dispositioned finding present in the current scan.
  def dispositioned(control_id, kind: "poam", **disp_attrs)
    create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
           control_id: control_id, severity: "HIGH")
    create(:finding_disposition, authorization_boundary: boundary, control_id: control_id,
           kind: kind, **disp_attrs)
  end

  describe "#export" do
    it "emits an Amendments doc with one override per current dispositioned finding" do
      dispositioned("CVE-1", kind: "poam", reason: "tracked", decided_by: "sec@corp.io")
      dispositioned("CVE-2", kind: "falsePositive", reason: "unreachable", decided_by: "@ghuser")

      doc = service.export

      expect(doc["version"]).to eq("1")
      # #1179 — keyed on the uuid (the hdf-system document's systemId), not the
      # slug, which is regenerated on rename and so cannot join anything.
      expect(doc["labels"]["system_id"]).to eq(boundary.uuid)
      expect(doc["labels"]["system_id"]).not_to eq(boundary.slug)
      expect(doc["overrides"].length).to eq(2)

      o1 = doc["overrides"].find { |o| o["requirementId"] == "CVE-1" }
      expect(o1["type"]).to eq("poam")
      expect(o1["status"]).to eq("failed")
      expect(o1["reason"]).to eq("tracked")
      expect(o1["appliedBy"]).to eq({ "type" => "email", "identifier" => "sec@corp.io" })

      o2 = doc["overrides"].find { |o| o["requirementId"] == "CVE-2" }
      expect(o2["type"]).to eq("falsePositive")
      expect(o2["status"]).to eq("notApplicable")
      # `username`, not `github`. This example asserted "github" until it was
      # measured against hdf-libs 3.7.0, which rejects it — the vocabulary is
      # email | username | system | agent | simple | other and "github" was
      # never in it. 3.5.1's `amend verify` did not check the field at all, so
      # the spec and the service agreed with each other and neither agreed with
      # hdf.
      expect(o2["appliedBy"]).to eq({ "type" => "username", "identifier" => "@ghuser" })

      # Pin the vocabulary itself, so the next wrong value fails here rather
      # than in a release gate.
      doc["overrides"].each do |o|
        expect(Hdf::AmendmentChain::IDENTITY_TYPES).to include(o.dig("appliedBy", "type"))
      end
    end

    it "chains the overrides so an edit after export is detectable" do
      dispositioned("CVE-1")
      dispositioned("CVE-2")
      overrides = service.export["overrides"]

      expect(overrides.size).to be >= 2
      expect(overrides.first).not_to have_key("previousChecksum")
      overrides.drop(1).each_with_index do |o, i|
        expect(o.dig("previousChecksum", "algorithm")).to eq("sha256")
        expect(o.dig("previousChecksum", "value"))
          .to eq(Hdf::AmendmentChain.checksum_json(overrides[i])),
              "override #{i + 1} is not linked to the one before it"
      end
    end

    # ── The refusal, both directions ──────────────────────────────────────
    #
    # hdf-libs 3.7.0 requires `expiresAt` on every override, and SPARC's model
    # only makes expiration mandatory for the clock kinds — so a falsePositive
    # can legitimately have none. That conflict is resolved by refusing, not by
    # inventing a date: a fabricated far-future expiry would satisfy the schema
    # and be untrue, which is the trade hdf-cli itself stopped making when it
    # stopped inventing POA&M deadlines.
    it "refuses to export a disposition with no expiry, and names it" do
      dispositioned("CVE-1")
      # The model now REFUSES to create one of these, so the scenario has to be
      # written past validation — which is exactly what it represents: a row
      # recorded before the rule existed. That is why the export keeps its own
      # guard instead of trusting the model, since validation only fires on
      # save and no save is coming for a row already on disk.
      legacy = dispositioned("CVE-NO-EXPIRY", kind: "falsePositive")
      legacy.update_column(:expiration, nil)

      expect { service.export(verify: false) }
        .to raise_error(HdfAmendmentExportService::UnexportableDisposition) { |e|
          expect(e.missing_expiry).to eq([ "CVE-NO-EXPIRY" ])
          expect(e.message).to include("no expiry set")
        }
    end

    it "refuses an expiry beyond the review window, and names it" do
      dispositioned("CVE-1")
      far = dispositioned("CVE-TOO-FAR", kind: "poam")
      # Past the validation, to represent a row that predates the rule.
      far.update_column(:expiration, far.decided_at + FindingDisposition::MAX_EXPIRATION_WINDOW + 1.day)

      expect { service.export(verify: false) }
        .to raise_error(HdfAmendmentExportService::UnexportableDisposition) { |e|
          expect(e.beyond_window).to eq([ "CVE-TOO-FAR" ])
        }
    end

    # The allow leg: the refusal must be the guard talking, not the export
    # refusing everything.
    it "exports when every disposition carries a review date" do
      dispositioned("CVE-1")
      dispositioned("CVE-2", kind: "falsePositive")

      doc = service.export(verify: false)

      expect(doc["overrides"].size).to eq(2)
      expect(doc["overrides"].map { |o| o["expiresAt"] }).to all(be_present)
    end

    it "orders overrides by requirementId (deterministic)" do
      dispositioned("CVE-9")
      dispositioned("CVE-1")
      dispositioned("CVE-5")
      expect(service.export["overrides"].map { |o| o["requirementId"] }).to eq(%w[CVE-1 CVE-5 CVE-9])
    end

    it "includes expiresAt for time-bounded dispositions" do
      finding = create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
                       control_id: "CVE-W", severity: "HIGH")
      create(:finding_disposition, :waiver, authorization_boundary: boundary, control_id: finding.control_id,
             expiration: 90.days.from_now)
      override = service.export["overrides"].first
      expect(override["expiresAt"]).to be_present
    end

    it "excludes dispositions whose control_id is not in the current scan" do
      dispositioned("CVE-1")
      # A disposition with no matching finding in this boundary's scan:
      create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-GONE", kind: "poam")
      expect(service.export["overrides"].map { |o| o["requirementId"] }).to eq(%w[CVE-1])
    end

    it "excludes expired dispositions" do
      finding = create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
                       control_id: "CVE-EXP", severity: "HIGH")
      create(:finding_disposition, :waiver, authorization_boundary: boundary,
             control_id: finding.control_id, expiration: 1.day.ago)
      expect(service.export["overrides"]).to be_empty
    end

    it "is deterministic: same dispositions produce the same amendmentId" do
      dispositioned("CVE-1")
      id1 = service.export["amendmentId"]
      id2 = described_class.new(boundary, runner: runner).export["amendmentId"]
      expect(id1).to eq(id2)
    end

    # #1037 — this asserted `kind_of(String)`, which was the defect written down.
    # `HdfRunner#with_input_path` treats a String as a PATH and hands it to the
    # CLI unchanged, so a JSON string arrived as a filename and every call to the
    # endpoint 422'd. The double could not notice: it verifies that the method
    # exists and takes one argument, not what the real implementation does with
    # it.
    #
    # So this now asserts the argument is something the real runner can OPEN,
    # and that what it carries is the emitted document.
    it "validates the emitted doc via hdf amend verify, passing it as readable content" do
      dispositioned("CVE-1")
      received = nil
      expect(runner).to receive(:amend_verify) { |arg| received = arg }.and_return(true)

      doc = service.export

      expect(received).to respond_to(:read),
        "a bare String is treated as a file PATH by HdfRunner, not as content (#1037)"
      expect(JSON.parse(received.read)).to eq(doc)
    end

    it "skips verification when verify: false" do
      dispositioned("CVE-1")
      expect(runner).not_to receive(:amend_verify)
      service.export(verify: false)
    end

    it "propagates a verification failure" do
      dispositioned("CVE-1")
      allow(runner).to receive(:amend_verify).and_raise(
        HdfRunner::Error.new("schema mismatch", command: "hdf amend verify", exit_code: 1, stderr: "bad")
      )
      expect { service.export }.to raise_error(HdfRunner::Error)
    end

    # #1179 — the amendment is bound to its system. systemRef is the URL of the
    # boundary's hdf-system document, keyed on the uuid so a rename does not
    # move it.
    it "carries systemRef pointing at the boundary's hdf-system document" do
      dispositioned("CVE-1")
      doc = service.export

      expect(doc["systemRef"]).to eq(
        "#{SparcConfig.app_url.chomp('/')}/api/v1/authorization_boundaries/#{boundary.uuid}/hdf_system"
      )
      expect(doc["systemRef"]).to eq(HdfSystemExportService.system_ref(boundary))
    end

    it "keeps systemRef and labels.system_id when the boundary is renamed" do
      dispositioned("CVE-1")
      before = service.export
      boundary.update!(name: "Renamed #{boundary.name}")

      after = described_class.new(boundary.reload, runner: runner).export
      expect(after["systemRef"]).to eq(before["systemRef"])
      expect(after.dig("labels", "system_id")).to eq(before.dig("labels", "system_id"))
    end
  end

  # The CLI is the authority on whether systemRef is a field an amendments
  # document may carry. Skipped, visibly, where no hdf binary exists (the CI
  # test runner — #835); the shipped image and a provisioned workstation run it.
  describe "with the real hdf binary" do
    before do
      skip "hdf-cli not on PATH (see #835); run in the image or after script/dev/install-hdf.sh" \
        unless HdfSystemExportService.cli_available?
    end

    it "passes `hdf amend verify` with systemRef and the uuid label" do
      dispositioned("CVE-1", decided_by: "sec@corp.io")
      doc = described_class.new(boundary, runner: HdfRunner.new).export

      expect(doc["systemRef"]).to be_present
    end

    # The refusal leg, so the pass above is the verifier talking rather than a
    # verifier that accepts anything.
    #
    # It cannot be a malformed systemRef. Measured on hdf-libs 3.7.0, neither
    # `hdf amend verify` nor `hdf validate --type amendments` asserts the
    # uri-reference format ("not a uri" passes), and neither refuses an
    # undefined top-level key. So the CLI's acceptance of systemRef proves the
    # field is ALLOWED, not that its value is checked — SPARC builds it from its
    # own route helper, which is what keeps it well-formed. The probe is a
    # vocabulary the CLI does enforce.
    it "is rejected by `hdf amend verify` when an override's identity type is outside the vocabulary" do
      dispositioned("CVE-1", decided_by: "sec@corp.io")
      doc = described_class.new(boundary, runner: runner).export
      doc["overrides"].first["appliedBy"]["type"] = "totally-bogus-not-a-type"

      expect { HdfRunner.new.amend_verify(StringIO.new(JSON.generate(doc))) }
        .to raise_error(HdfRunner::Error)
    end
  end
end
