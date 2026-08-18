require "rails_helper"

RSpec.describe Attestation, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:attester_name) }
    it { is_expected.to validate_presence_of(:statement) }
    it { is_expected.to validate_presence_of(:attested_at) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:evidence) }
  end

  # #947 — the hardcoded ROLES list is gone. It was invented with the original
  # evidence feature and never reconciled with either role system: `control_owner`
  # existed in NEITHER the canonical Role catalog nor the membership vocabulary,
  # so an attestation could name a role nobody could hold and no check could pass.
  # Who may attest is now derived from the `evidence.attest` permission.
  describe ".attestable_roles" do
    it "is derived from the permission, not a hardcoded list" do
      expect(Attestation.const_defined?(:ROLES)).to be(false)
    end

    it "includes a boundary role granted evidence.attest" do
      role = create(:role, :authorization_boundary_scoped,
                    permissions: { "evidence.attest" => true })

      expect(Attestation.attestable_roles).to include(role)
    end

    it "excludes a boundary role without the permission" do
      role = create(:role, :authorization_boundary_scoped,
                    permissions: { "evidence.write" => true })

      expect(Attestation.attestable_roles).not_to include(role)
    end

    # An instance-scoped grant satisfies has_permission? on EVERY boundary, so
    # honouring it for a boundary would be estate-wide signing authority. It is
    # admitted only for instance-wide (provider / leveraged-SSP) evidence, which
    # belongs to no single system.
    it "excludes an instance-scoped role when attesting against a boundary" do
      boundary = create(:authorization_boundary)
      role = create(:role, permissions: { "evidence.attest" => true })

      expect(Attestation.attestable_roles(authorization_boundary_id: boundary.id)).not_to include(role)
    end

    it "admits an instance-scoped role for instance-wide evidence" do
      role = create(:role, permissions: { "evidence.attest" => true })

      expect(Attestation.attestable_roles(authorization_boundary_id: nil)).to include(role)
    end
  end

  describe "FREQUENCIES" do
    it "covers the CMS attestation cadence vocabulary" do
      expect(Attestation::FREQUENCIES).to contain_exactly(
        "daily", "weekly", "monthly", "quarterly", "annually", "ad_hoc"
      )
    end

    it "accepts a valid frequency" do
      expect(build(:attestation, frequency: "annually")).to be_valid
    end

    it "rejects an unknown frequency" do
      attestation = build(:attestation, frequency: "fortnightly")
      expect(attestation).not_to be_valid
      expect(attestation.errors[:frequency]).to be_present
    end

    it "allows nil frequency (optional)" do
      expect(build(:attestation, frequency: nil)).to be_valid
    end
  end

  describe "STATUSES" do
    it "limits to passed/failed" do
      expect(Attestation::STATUSES).to contain_exactly("passed", "failed")
    end

    it "defaults to passed" do
      attestation = create(:attestation)
      expect(attestation.status).to eq("passed")
    end

    it "accepts failed" do
      expect(build(:attestation, status: "failed")).to be_valid
    end

    it "rejects unknown status" do
      attestation = build(:attestation, status: "pending")
      expect(attestation).not_to be_valid
      expect(attestation.errors[:status]).to be_present
    end
  end

  describe "#frequency_label" do
    it "returns the human-readable label" do
      expect(build(:attestation, frequency: "annually").frequency_label).to eq("Annually")
    end

    it "returns nil when frequency is nil" do
      expect(build(:attestation, frequency: nil).frequency_label).to be_nil
    end
  end

  describe "#role_label" do
    it "returns the catalog display name for a known role" do
      create(:role, :authorization_boundary_scoped, name: "isso", display_name: "ISSO")
      attestation = build(:attestation, role: "isso")

      expect(attestation.role_label).to eq("ISSO")
    end

    it "returns titleized role for unknown role" do
      attestation = build(:attestation, role: "custom_role")
      expect(attestation.role_label).to eq("Custom Role")
    end

    it "returns Unknown for nil role" do
      attestation = build(:attestation, role: nil)
      expect(attestation.role_label).to eq("Unknown")
    end
  end

  # #947 — the point of the issue. `evidence.write` is the permission to ADD an
  # attestation; it is not the authority to MAKE the assertion. These prove BOTH
  # directions: the check passes where it should, and — more importantly — fails
  # where it should, because a guard only ever tested in its passing direction
  # is indistinguishable from no guard at all.
  describe "attester verification" do
    let(:boundary)      { create(:authorization_boundary) }
    let(:other_boundary) { create(:authorization_boundary) }
    let(:evidence)      { create(:evidence, authorization_boundary: boundary) }
    let(:attester)      { create(:user) }

    let(:attesting_role) do
      create(:role, :authorization_boundary_scoped,
             name: "so_iso", display_name: "System Owner / ISO",
             permissions: { "evidence.attest" => true })
    end

    let(:non_attesting_role) do
      create(:role, :authorization_boundary_scoped,
             name: "view_only", display_name: "View Only",
             permissions: { "evidence.read" => true })
    end

    def attestation_for(role_name)
      build(:attestation, evidence: evidence, attester_user: attester,
                          role: role_name, grant_boundary_id: nil)
    end

    it "accepts an attester who holds an attesting role on the boundary" do
      create(:user_role, user: attester, role: attesting_role, authorization_boundary: boundary)

      expect(attestation_for("so_iso")).to be_valid
    end

    it "rejects an attester who holds no role on the boundary" do
      attestation = attestation_for("so_iso")
      attesting_role # ensure the role exists, but grant it to nobody

      expect(attestation).not_to be_valid
      expect(attestation.errors[:role].join).to match(/holds no role/i)
    end

    # The boundary-scoping check. Holding the role SOMEWHERE is not holding it
    # HERE, and conflating the two would make the roster check decorative.
    it "rejects an attester who holds the role on a DIFFERENT boundary" do
      create(:user_role, user: attester, role: attesting_role, authorization_boundary: other_boundary)

      attestation = attestation_for("so_iso")
      expect(attestation).not_to be_valid
      expect(attestation.errors[:role]).to be_present
    end

    it "rejects a role that exists but does not carry evidence.attest" do
      create(:user_role, user: attester, role: non_attesting_role, authorization_boundary: boundary)

      attestation = attestation_for("view_only")
      expect(attestation).not_to be_valid
      expect(attestation.errors[:role].join).to match(/not a role that may attest/i)
    end

    it "rejects an attestation with no resolved account" do
      attestation = build(:attestation, :unverified, evidence: evidence)

      expect(attestation).not_to be_valid
      expect(attestation.errors[:attester_user]).to be_present
    end

    # The disposition decided for #947: legacy rows stay READABLE, and are
    # blocked only when re-saved. Reporting history is not the same as accepting
    # a new claim.
    context "a legacy row recorded under the retired vocabulary" do
      let!(:legacy) do
        attestation = build(:attestation, :legacy_control_owner, evidence: evidence)
        attestation.save!(validate: false)
        attestation
      end

      it "stays readable and renders its recorded role" do
        expect(legacy.reload.role_label).to eq("Control Owner")
      end

      it "is reported as unverified rather than rewritten" do
        expect(legacy.reload.attester_verified?).to be(false)
        expect(legacy.reload.attester_name).to be_present
      end

      it "cannot be re-saved without resolving the attester" do
        legacy.statement = "amended statement"

        expect(legacy.save).to be(false)
        expect(legacy.errors[:attester_user]).to be_present
      end
    end

    # #934 — the snapshot rule. A later rename must not rewrite what the record
    # said at the moment it was signed.
    it "snapshots the attester name and never rewrites it on a later rename" do
      create(:user_role, user: attester, role: attesting_role, authorization_boundary: boundary)
      attester.update!(display_name: "Original Name")

      attestation = attestation_for("so_iso")
      attestation.save!
      expect(attestation.attester_name).to eq("Original Name")

      attester.update!(display_name: "Renamed Later")
      attestation.reload.update!(statement: "amended")

      expect(attestation.reload.attester_name).to eq("Original Name")
    end

    # Every other guard in the app is a no-op with no auth method enabled; a
    # single-operator instance must not be locked out of its own evidence.
    it "does not fire when no auth method is enabled" do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(false)

      expect(build(:attestation, :unverified, evidence: evidence)).to be_valid
    end
  end

  # #947 — instance-wide evidence is PROVIDER material (a leveraged SSP), so it
  # has its own authority chain rather than borrowing a boundary's. These prove
  # the asymmetry: Policy reaches global evidence, and must NOT thereby reach an
  # individual system's.
  describe "attesting on instance-wide evidence" do
    let(:global_evidence)   { create(:evidence, authorization_boundary: nil) }
    let(:boundary)          { create(:authorization_boundary) }
    let(:boundary_evidence) { create(:evidence, authorization_boundary: boundary) }

    let(:policy_role) do
      create(:role, name: "policy_manager", display_name: "Policy Manager",
                    scope: "instance", permissions: { "evidence.attest" => true })
    end

    let(:policy_user) { create(:user) }

    before { create(:user_role, user: policy_user, role: policy_role, authorization_boundary: nil) }

    it "accepts an instance-scoped Policy attester on global evidence" do
      attestation = build(:attestation, evidence: global_evidence, attester_user: policy_user,
                                        role: "policy_manager", grant_boundary_id: nil)

      expect(attestation).to be_valid
    end

    # The asymmetry. An instance grant satisfies has_permission? on EVERY
    # boundary, so if the model leaned on that alone, Policy would silently gain
    # authority to sign for every system on the instance.
    it "refuses that same Policy attester on a specific boundary's evidence" do
      attestation = build(:attestation, evidence: boundary_evidence, attester_user: policy_user,
                                        role: "policy_manager", grant_boundary_id: nil)

      expect(attestation).not_to be_valid
      expect(attestation.errors[:role]).to be_present
    end

    it "accepts a boundary role holder attesting on global evidence" do
      ciso = create(:role, :authorization_boundary_scoped, name: "ciso", display_name: "CISO",
                           permissions: { "evidence.attest" => true })
      user = create(:user)
      create(:user_role, user: user, role: ciso, authorization_boundary: boundary)

      attestation = build(:attestation, evidence: global_evidence, attester_user: user,
                                        role: "ciso", grant_boundary_id: nil)

      expect(attestation).to be_valid
    end
  end

  # An Instance Admin clears `authorize_permission!` everywhere else in the app;
  # attesting is not the one place that silently differs.
  describe "an Instance Admin attester" do
    let(:boundary) { create(:authorization_boundary) }
    let(:evidence) { create(:evidence, authorization_boundary: boundary) }
    let(:admin)    { create(:user, :admin) }

    let!(:attesting_role) do
      create(:role, :authorization_boundary_scoped, name: "so_iso", display_name: "System Owner / ISO",
                    permissions: { "evidence.attest" => true })
    end

    it "may attest without holding the role on the roster" do
      attestation = build(:attestation, evidence: evidence, attester_user: admin,
                                        role: "so_iso", grant_boundary_id: nil)

      expect(attestation).to be_valid
    end

    # The bypass is on WHO holds the role, not on what the vocabulary contains.
    # An admin still cannot invent an authority the instance does not recognise.
    it "still cannot attest under a role that carries no attest permission" do
      create(:role, :authorization_boundary_scoped, name: "view_only", display_name: "View Only",
                    permissions: { "evidence.read" => true })

      attestation = build(:attestation, evidence: evidence, attester_user: admin,
                                        role: "view_only", grant_boundary_id: nil)

      expect(attestation).not_to be_valid
      expect(attestation.errors[:role].join).to match(/not a role that may attest/i)
    end

    it "appears in the attester picker even with no roster grant" do
      expect(Attestation.eligible_attesters_for(authorization_boundary_id: boundary.id)).to include(admin)
    end
  end

  describe "#generate_signature!" do
    it "generates a SHA-256 signature hash" do
      attestation = create(:attestation)
      attestation.generate_signature!

      expect(attestation.signature_hash).to be_present
      expect(attestation.signature_hash.length).to eq(64)
    end

    it "produces consistent hashes for the same data" do
      attestation = create(:attestation)
      attestation.generate_signature!
      first_hash = attestation.signature_hash

      attestation.generate_signature!
      expect(attestation.signature_hash).to eq(first_hash)
    end
  end
end
