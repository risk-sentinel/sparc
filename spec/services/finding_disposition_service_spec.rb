# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindingDispositionService do
  let(:boundary) { create(:authorization_boundary) }
  let(:scan_run) { create(:scan_run, authorization_boundary: boundary) }
  let(:finding) do
    create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
           control_id: "CVE-1", severity: "HIGH")
  end
  let(:service) { described_class.new(finding) }

  # #947 — an attestation now references an account holding a real attesting
  # role, and the Authorizing Official is seeded canonically as `ao`, not under
  # the retired `authorizing_official` spelling.
  let(:ao_role) do
    create(:role, :authorization_boundary_scoped, name: "ao",
           display_name: "Authorizing Official",
           permissions: { "evidence.attest" => true })
  end

  let(:ao_user) { create(:user, display_name: "Ada Officer") }

  let(:ao_attestation) do
    create(:user_role, user: ao_user, role: ao_role,
           authorization_boundary: create(:authorization_boundary))
    create(:attestation, attester_user: ao_user, role: "ao", grant_boundary_id: nil)
  end

  describe "#upsert linkage rules" do
    it "creates a falsePositive linked to Evidence" do
      disp = service.upsert(kind: "falsePositive", reason: "scanner wrong",
                            decided_by: "a@b.co", linked_subject: create(:evidence))
      expect(disp).to be_persisted
      expect(disp.kind).to eq("falsePositive")
      expect(disp.signature_hash).to be_present
      expect(disp.hdf_status).to eq("notApplicable")
    end

    it "creates a waiver linked to an AO attestation with expiration" do
      disp = service.upsert(kind: "waiver", reason: "risk accepted", decided_by: "a@b.co",
                            linked_subject: ao_attestation, expiration: 90.days.from_now)
      expect(disp.kind).to eq("waiver")
    end

    it "rejects a waiver whose attestation is not an AO" do
      # A real, valid attestation — by someone who simply is not the AO. The
      # rule under test is "only an AO may accept residual risk", so the
      # rejection must come from the disposition rule, not from the attestation
      # failing to save for an unrelated reason.
      isso_role = create(:role, :authorization_boundary_scoped, name: "isso",
                         display_name: "ISSO", permissions: { "evidence.attest" => true })
      isso_user = create(:user)
      create(:user_role, user: isso_user, role: isso_role,
             authorization_boundary: create(:authorization_boundary))
      non_ao = create(:attestation, attester_user: isso_user, role: "isso", grant_boundary_id: nil)

      expect {
        service.upsert(kind: "waiver", reason: "x", decided_by: "a@b.co",
                       linked_subject: non_ao,
                       expiration: 90.days.from_now)
      }.to raise_error(described_class::DispositionError, /Authorizing Official/i)
    end

    it "creates a poam linked to a PoamFinding" do
      disp = service.upsert(kind: "poam", reason: "tracked", decided_by: "a@b.co",
                            linked_subject: create(:poam_finding))
      expect(disp.kind).to eq("poam")
      expect(disp.hdf_status).to eq("failed")
    end

    it "creates a riskAdjustment linked to a RiskAssessment" do
      disp = service.upsert(kind: "riskAdjustment", reason: "downgraded", decided_by: "a@b.co",
                            linked_subject: create(:risk_assessment, authorization_boundary: boundary))
      expect(disp.kind).to eq("riskAdjustment")
    end

    it "creates an inherited disposition linked to an upstream boundary" do
      disp = service.upsert(kind: "inherited", reason: "provided upstream", decided_by: "a@b.co",
                            linked_subject: create(:authorization_boundary))
      expect(disp.kind).to eq("inherited")
    end

    it "requires a linked subject" do
      expect { service.upsert(kind: "falsePositive", reason: "x", decided_by: "a@b.co") }
        .to raise_error(described_class::DispositionError, /requires a linked Evidence/)
    end

    it "rejects a mismatched linked subject type" do
      expect {
        service.upsert(kind: "poam", reason: "x", decided_by: "a@b.co", linked_subject: create(:evidence))
      }.to raise_error(described_class::DispositionError, /must link a PoamFinding/)
    end
  end

  describe "severity policy" do
    let(:finding) do
      create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
             control_id: "CVE-CRIT", severity: "CRITICAL")
    end

    it "bans waiver/riskAdjustment/operationalRequirement on CRITICAL findings" do
      %w[waiver operationalRequirement].each do |kind|
        expect {
          service.upsert(kind: kind, reason: "x", decided_by: "a@b.co",
                         linked_subject: ao_attestation, expiration: 90.days.from_now)
        }.to raise_error(described_class::DispositionError, /CRITICAL/)
      end
    end

    it "allows falsePositive on CRITICAL findings" do
      disp = service.upsert(kind: "falsePositive", reason: "unreachable", decided_by: "a@b.co",
                            linked_subject: create(:evidence))
      expect(disp).to be_persisted
    end
  end

  describe "idempotency" do
    it "updates the single disposition for (boundary, control_id)" do
      service.upsert(kind: "poam", reason: "first", decided_by: "a@b.co", linked_subject: create(:poam_finding))
      service.upsert(kind: "falsePositive", reason: "second", decided_by: "a@b.co", linked_subject: create(:evidence))

      dispositions = FindingDisposition.where(authorization_boundary: boundary, control_id: "CVE-1")
      expect(dispositions.count).to eq(1)
      expect(dispositions.first.kind).to eq("falsePositive")
      expect(dispositions.first.reason).to eq("second")
    end
  end

  describe ".resolve_subject" do
    it "resolves a whitelisted type" do
      ev = create(:evidence)
      expect(described_class.resolve_subject("Evidence", ev.id)).to eq(ev)
    end

    it "returns nil when type or id is blank" do
      expect(described_class.resolve_subject(nil, nil)).to be_nil
    end

    it "rejects a non-whitelisted type" do
      expect { described_class.resolve_subject("User", 1) }
        .to raise_error(described_class::DispositionError, /Unsupported/)
    end
  end
end
