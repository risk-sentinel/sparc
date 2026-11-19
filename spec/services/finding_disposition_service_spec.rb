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

  def decide(**args)
    service.upsert(nist: nist_params(args[:kind]), **args)
  end

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
      disp = decide(kind: "falsePositive", reason: "scanner wrong",
                            decided_by: "a@b.co", linked_subject: create(:evidence),
                            expiration: 90.days.from_now)
      expect(disp).to be_persisted
      expect(disp.kind).to eq("falsePositive")
      expect(disp.signature_hash).to be_present
      expect(disp.hdf_status).to eq("notApplicable")
    end

    it "creates a waiver linked to an AO attestation with expiration" do
      disp = decide(kind: "waiver", reason: "risk accepted", decided_by: "a@b.co",
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
        decide(kind: "waiver", reason: "x", decided_by: "a@b.co",
                       linked_subject: non_ao,
                       expiration: 90.days.from_now)
      }.to raise_error(described_class::DispositionError, /Authorizing Official/i)
    end

    it "creates a poam linked to a PoamFinding" do
      disp = decide(kind: "poam", reason: "tracked", decided_by: "a@b.co",
                            linked_subject: create(:poam_finding), expiration: 90.days.from_now)
      expect(disp.kind).to eq("poam")
      expect(disp.hdf_status).to eq("failed")
    end

    it "creates a riskAdjustment linked to a RiskAssessment, with its adjusted impact" do
      disp = decide(kind: "riskAdjustment", reason: "downgraded", decided_by: "a@b.co",
                            linked_subject: create(:risk_assessment, authorization_boundary: boundary),
                            expiration: 90.days.from_now, adjusted_impact: "0.3")
      expect(disp.kind).to eq("riskAdjustment")
      expect(disp.adjusted_impact).to eq(BigDecimal("0.3"))
    end

    # #1368 — hdf-cli 3.8.0 requires the re-rated impact on a riskAdjustment.
    it "refuses a riskAdjustment without an adjusted impact" do
      expect {
        decide(kind: "riskAdjustment", reason: "downgraded", decided_by: "a@b.co",
                       linked_subject: create(:risk_assessment, authorization_boundary: boundary),
                       expiration: 90.days.from_now)
      }.to raise_error(described_class::DispositionError, /Adjusted impact can't be blank/)
    end

    it "binds the adjusted impact into the signature, and leaves other signatures as they were" do
      assessment = create(:risk_assessment, authorization_boundary: boundary)
      args = { kind: "riskAdjustment", reason: "downgraded", decided_by: "a@b.co",
               linked_subject: assessment, expiration: Time.utc(2027, 1, 1) }
      low = decide(**args, adjusted_impact: "0.3").signature_hash
      high = decide(**args, adjusted_impact: "0.5").signature_hash
      expect(low).not_to eq(high)

      # A disposition from before #1368 (no adjusted impact, no NIST fields)
      # signs exactly as it always did.
      older = build(:finding_disposition, :without_nist, authorization_boundary: boundary, control_id: "CVE-1",
                    kind: "poam", reason: "tracked", decided_by: "a@b.co",
                    linked_subject: create(:poam_finding), expiration: Time.utc(2027, 1, 1))
      legacy = Digest::SHA256.hexdigest([ boundary.id, "CVE-1", "poam", "tracked",
                                          older.linked_subject_type, older.linked_subject_id,
                                          older.expiration.utc.iso8601, "a@b.co" ].join("|"))
      expect(service.send(:signature_for, older)).to eq(legacy)
    end

    # #1368 — how the POA&M risk is said in NIST OSCAL, required and signed.
    describe "NIST POA&M fields" do
      let(:poam_args) do
        { kind: "poam", reason: "tracked", decided_by: "a@b.co",
          linked_subject: create(:poam_finding), expiration: Time.utc(2027, 1, 1) }
      end

      it "refuses a disposition without them, naming each" do
        expect { service.upsert(**poam_args, nist: nist_params("poam").except(:nist_likelihood, :nist_impact)) }
          .to raise_error(described_class::DispositionError, /required: nist_likelihood, nist_impact/)
      end

      it "stores them and derives the risk level" do
        disp = decide(**poam_args)
        expect(disp).to have_attributes(nist_risk_status: "deviation-requested", nist_likelihood: "moderate",
                                        nist_impact: "high", nist_risk_level: "moderate")
      end

      it "refuses a value that is not NIST's" do
        expect { service.upsert(**poam_args, nist: nist_params("poam").merge(nist_risk_status: "pending")) }
          .to raise_error(described_class::DispositionError, /Nist risk status is not included/)
      end

      it "binds them into the signature" do
        planned = decide(**poam_args).signature_hash
        completed = service.upsert(**poam_args, nist: nist_params("poam").merge(nist_response_lifecycle: "completed"))
        expect(completed.signature_hash).not_to eq(planned)
      end

      it "keeps false-positive for a falsePositive, and only for it" do
        expect { service.upsert(**poam_args, nist: nist_params("poam").merge(nist_risk_prop: "false-positive")) }
          .to raise_error(described_class::DispositionError, /false-positive is only for a falsePositive/)
        evidence = create(:evidence)
        expect {
          service.upsert(kind: "falsePositive", reason: "unreachable", decided_by: "a@b.co", linked_subject: evidence,
                         expiration: 90.days.from_now, nist: nist_params("poam"))
        }.to raise_error(described_class::DispositionError, /must be false-positive for a falsePositive/)
      end
    end

    it "creates an attestation linked to an Attestation" do
      disp = decide(kind: "attestation", reason: "verified by the assessor", decided_by: "a@b.co",
                    linked_subject: create(:attestation), expiration: 90.days.from_now)
      expect(disp).to have_attributes(kind: "attestation", hdf_status: "passed")
    end

    it "creates an inherited disposition linked to an upstream boundary" do
      disp = decide(kind: "inherited", reason: "provided upstream", decided_by: "a@b.co",
                            linked_subject: create(:authorization_boundary),
                            expiration: 90.days.from_now)
      expect(disp.kind).to eq("inherited")
    end

    it "requires a linked subject" do
      expect { decide(kind: "falsePositive", reason: "x", decided_by: "a@b.co") }
        .to raise_error(described_class::DispositionError, /requires a linked Evidence/)
    end

    it "rejects a mismatched linked subject type" do
      expect {
        decide(kind: "poam", reason: "x", decided_by: "a@b.co", linked_subject: create(:evidence))
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
          decide(kind: kind, reason: "x", decided_by: "a@b.co",
                         linked_subject: ao_attestation, expiration: 90.days.from_now)
        }.to raise_error(described_class::DispositionError, /CRITICAL/)
      end
    end

    it "allows falsePositive on CRITICAL findings" do
      disp = decide(kind: "falsePositive", reason: "unreachable", decided_by: "a@b.co",
                            linked_subject: create(:evidence), expiration: 90.days.from_now)
      expect(disp).to be_persisted
    end
  end

  describe "idempotency" do
    it "updates the single disposition for (boundary, control_id)" do
      decide(kind: "poam", reason: "first", decided_by: "a@b.co",
                     linked_subject: create(:poam_finding), expiration: 90.days.from_now)
      decide(kind: "falsePositive", reason: "second", decided_by: "a@b.co",
                     linked_subject: create(:evidence), expiration: 90.days.from_now)

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
