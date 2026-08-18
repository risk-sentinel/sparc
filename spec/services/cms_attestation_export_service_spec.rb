require "rails_helper"

RSpec.describe CmsAttestationExportService do
  # #947 — the evidence factory links a control by default (evidence must
  # support one). These specs assert on exactly the links they create, so the
  # default is suppressed and the FIRST link each one makes satisfies the rule.
  # #947 — the evidence factory links one control by default, because evidence
  # must support one. Each example NAMES that link via `control_id:` rather than
  # adding a second on top of an unpredictable default, so the assertions stay
  # about exactly the links the example set up.
  def evidence_linked_to(control_id, **attrs)
    create(:evidence, control_id: control_id, **attrs)
  end

  # The pre-rule state: a persisted row with no links at all. Reachable only by
  # skipping validation, which is precisely what makes it a legacy row.
  def unlinked_evidence
    record = build(:evidence, :without_control_links)
    record.slug = "cms-unlinked-#{SecureRandom.hex(4)}"
    record.save!(validate: false)
    record
  end

  # A real attester holding a real attesting role, since an attestation now
  # references an account rather than a typed-in name.
  let(:attester) { create(:user, display_name: "Jane Reviewer") }

  let!(:isso_role) do
    role = create(:role, :authorization_boundary_scoped, name: "isso", display_name: "ISSO",
                  permissions: { "evidence.attest" => true })
    create(:user_role, user: attester, role: role,
           authorization_boundary: create(:authorization_boundary))
    role
  end

  describe "#call" do
    context "when the attestation's evidence has multiple control links" do
      it "denormalizes one record per linked control_id" do
        evidence = evidence_linked_to("AC-2")
        evidence.evidence_control_links.create!(control_id: "AC-3")
        attestation = create(:attestation, evidence: evidence,
                             frequency: "annually", status: "passed")

        records = described_class.new(Attestation.where(id: attestation.id)).call

        expect(records.length).to eq(2)
        expect(records.map { |r| r[:control_id] }).to contain_exactly("AC-2", "AC-3")
      end
    end

    # #911 — CONTRACT, not an incidental value.
    #
    # Control identifiers are stored canonically (`ca-7`) so internal
    # comparisons stop failing silently. This payload is consumed downstream by
    # Heimdall, which keys on the NIST tag, so it must keep emitting the padded
    # form regardless of how SPARC stores it. If this spec goes red because the
    # storage form leaked into the export, the fix is in the service — not here.
    context "the emitted identifier is the CMS form, not SPARC's storage form" do
      it "emits the padded NIST form even when the link is stored canonically" do
        evidence = evidence_linked_to("ca-7")
        attestation = create(:attestation, evidence: evidence)

        records = described_class.new(Attestation.where(id: attestation.id)).call

        expect(records.first[:control_id]).to eq("CA-7")
      end

      # Heimdall matches on the NIST tag, which has NO space before the
      # enhancement. `ControlId.human` renders publication spacing
      # ("AC-2 (1)") — right for prose, wrong for a tag match — so the export
      # uses `nist_tag` and this pins the difference.
      it "renders an enhancement as a NIST tag, without a space" do
        ev = evidence_linked_to("ac-2.1", title: "CMS enhancement")
        att = create(:attestation, evidence: ev)

        records = described_class.new(Attestation.where(id: att.id)).call

        expect(records.first[:control_id]).to eq("AC-2(1)")
      end

      it "emits the same identifier however the link was entered" do
        %w[AC-2 ac-2 AC-02].each_with_index do |form, i|
          ev = evidence_linked_to(form, title: "CMS form #{i}")
          att = create(:attestation, evidence: ev)

          records = described_class.new(Attestation.where(id: att.id)).call

          expect(records.first[:control_id]).to eq("AC-2"),
            "entering #{form.inspect} changed what the CMS consumer receives"
        end
      end
    end

    context "when the attestation's evidence has no control links" do
      it "emits zero records" do
        attestation = create(:attestation, evidence: unlinked_evidence)
        records = described_class.new(Attestation.where(id: attestation.id)).call
        expect(records).to be_empty
      end
    end

    it "maps SPARC fields to the CMS schema shape" do
      evidence = evidence_linked_to("CA-7")
      attestation = create(:attestation,
                           evidence: evidence,
                           attester_user: attester, role: "isso",
                           grant_boundary_id: nil,
                           statement: "All controls verified.",
                           attested_at: Time.utc(2026, 4, 1, 12, 0, 0),
                           frequency: "quarterly",
                           status: "passed")

      record = described_class.new(Attestation.where(id: attestation.id)).call.first

      expect(record).to include(
        control_id: "CA-7",
        explanation: "All controls verified.",
        frequency: "quarterly",
        status: "passed",
        updated: "2026-04-01T12:00:00Z",
        updated_by: "Jane Reviewer (ISSO)"
      )
    end

    it "defaults frequency to ad_hoc when not set" do
      evidence = evidence_linked_to("CA-7")
      attestation = create(:attestation, evidence: evidence, frequency: nil)

      record = described_class.new(Attestation.where(id: attestation.id)).call.first
      expect(record[:frequency]).to eq("ad_hoc")
    end

    it "omits the role suffix from updated_by when role is blank" do
      evidence = evidence_linked_to("CA-7")
      # A blank role is a pre-#947 shape, so it is written as one: validation
      # now requires a role, and skipping it is what makes this a legacy row.
      attestation = build(:attestation, evidence: evidence, attester_name: "Anon", role: nil)
      attestation.save!(validate: false)

      record = described_class.new(Attestation.where(id: attestation.id)).call.first
      expect(record[:updated_by]).to eq("Anon")
    end

    it "iterates all attestations in the scope" do
      evidence = evidence_linked_to("AC-2")
      # The grant has to exist BEFORE the attestation is validated, not after.
      users = %w[A B].map do |name|
        user = create(:user, display_name: name)
        create(:user_role, user: user, role: isso_role,
               authorization_boundary: create(:authorization_boundary))
        user
      end
      a1, a2 = users.map do |user|
        create(:attestation, evidence: evidence, attester_user: user,
                             role: "isso", grant_boundary_id: nil)
      end

      records = described_class.new(Attestation.where(id: [ a1.id, a2.id ])).call
      expect(records.map { |r| r[:updated_by] }).to contain_exactly("A (ISSO)", "B (ISSO)")
    end
  end

  describe "#to_json" do
    it "serializes the records array" do
      evidence = evidence_linked_to("AC-2")
      create(:attestation, evidence: evidence, frequency: "annually")

      json = described_class.new.to_json
      parsed = JSON.parse(json)
      expect(parsed).to be_an(Array)
      expect(parsed.first).to include("control_id" => "AC-2", "frequency" => "annually")
    end
  end
end
