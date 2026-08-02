require "rails_helper"

RSpec.describe AuthorizationBoundaryMembership, type: :model do
  # dotenv loads in the test environment (config/application.rb:31), so the
  # committed .env can leak SPARC_AUTH_BOUNDARY_ROLES into these examples. Every
  # one of them sets the variable explicitly instead of inheriting whatever this
  # machine happens to hold — #875 was mis-triaged once already by reading
  # behaviour off one developer's .env.
  around do |example|
    original = ENV["SPARC_AUTH_BOUNDARY_ROLES"]
    ENV.delete("SPARC_AUTH_BOUNDARY_ROLES")
    example.run
  ensure
    original.nil? ? ENV.delete("SPARC_AUTH_BOUNDARY_ROLES") : ENV["SPARC_AUTH_BOUNDARY_ROLES"] = original
  end

  def configure_roles(value)
    ENV["SPARC_AUTH_BOUNDARY_ROLES"] = value
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:user_name) }
    it { is_expected.to validate_presence_of(:role) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:authorization_boundary) }
  end

  describe "roles" do
    it "has 7 default authorization-boundary-level RMF roles" do
      expect(described_class::DEFAULT_ROLES).to contain_exactly(
        "authorizing_official", "system_owner", "ciso", "isso",
        "project_member", "assessor", "view_only"
      )
    end
  end

  # #875 — form is normalized mechanically; vocabulary lives in a table. The
  # split matters: over-eager matching would silently collapse a role an
  # operator deliberately created.
  describe ".resolve_role" do
    it "passes a built-in key through unchanged" do
      expect(described_class.resolve_role("isso")).to eq("isso")
    end

    it "folds case, so ISSO and isso are one role" do
      expect(described_class.resolve_role("ISSO")).to eq("isso")
      expect(described_class.resolve_role("CISO")).to eq("ciso")
    end

    it "folds separators and punctuation" do
      expect(described_class.resolve_role("View Only")).to eq("view_only")
      expect(described_class.resolve_role("system-owner")).to eq("system_owner")
    end

    it "resolves the built-in human labels" do
      expect(described_class.resolve_role("Authorizing Official (AO)")).to eq("authorizing_official")
      expect(described_class.resolve_role("Assessor / 3PAO")).to eq("assessor")
      expect(described_class.resolve_role("Team Member")).to eq("project_member")
      expect(described_class.resolve_role("System Owner (SO/ISO)")).to eq("system_owner")
    end

    it "resolves the abbreviations, which no label spells out verbatim" do
      expect(described_class.resolve_role("AO")).to eq("authorizing_official")
      expect(described_class.resolve_role("3PAO")).to eq("assessor")
      # The spelling .env.example shipped, which is not the label string.
      expect(described_class.resolve_role("System Owner (SO)")).to eq("system_owner")
    end

    it "keeps a genuine custom role instead of correcting it" do
      expect(described_class.resolve_role("Security Champion")).to eq("security_champion")
    end

    it "does not collapse a role that merely resembles a built-in one" do
      expect(described_class.resolve_role("Assessor / Independent")).to eq("assessor_independent")
      expect(described_class.resolve_role("Deputy AO")).to eq("deputy_ao")
    end
  end

  describe ".available_roles (the dropdown)" do
    it "offers all seven defaults when unconfigured" do
      expect(described_class.available_roles).to eq(described_class::DEFAULT_ROLES)
    end

    it "subsets the defaults when configured with fewer" do
      configure_roles("isso,system_owner")
      expect(described_class.available_roles).to eq(%w[isso system_owner])
    end

    it "extends the list with custom roles" do
      configure_roles("isso,Security Champion")
      expect(described_class.available_roles).to eq(%w[isso security_champion])
    end

    it "de-duplicates entries that differ only in form" do
      configure_roles("ISSO, isso, Isso")
      expect(described_class.available_roles).to eq(%w[isso])
    end

    it "accepts the label form our own .env.example shipped" do
      configure_roles("Assessor / 3PAO, Authorizing Official (AO), CISO, ISSO, Team Member, System Owner (SO), View Only")
      expect(described_class.available_roles).to contain_exactly(
        "assessor", "authorizing_official", "ciso", "isso",
        "project_member", "system_owner", "view_only"
      )
    end
  end

  describe ".acceptable_roles (what the model will store)" do
    it "keeps every default acceptable even when the dropdown subsets them" do
      configure_roles("isso")
      expect(described_class.available_roles).to eq(%w[isso])
      expect(described_class.acceptable_roles).to include(*described_class::DEFAULT_ROLES)
    end

    it "includes configured custom roles" do
      configure_roles("Security Champion")
      expect(described_class.acceptable_roles).to include("security_champion")
    end
  end

  describe "role validation" do
    let(:boundary) { create(:authorization_boundary) }

    it "accepts a configured custom role" do
      configure_roles("Security Champion")
      membership = build(:authorization_boundary_membership, authorization_boundary: boundary, role: "Security Champion")
      expect(membership).to be_valid
      expect(membership.tap(&:validate).role).to eq("security_champion")
    end

    it "refuses a role that is neither built in nor configured" do
      configure_roles("isso")
      membership = build(:authorization_boundary_membership, authorization_boundary: boundary, role: "Security Champion")

      expect(membership).not_to be_valid
      expect(membership.errors[:role]).to include("is not an available role")
    end

    it "still accepts a default role the dropdown currently hides" do
      configure_roles("isso")
      membership = build(:authorization_boundary_membership, authorization_boundary: boundary, role: "ciso")
      expect(membership).to be_valid
    end

    # The reason the inclusion check is guarded by role_changed?. Retiring a role
    # from the configuration must not strand the rows already holding it — every
    # later save of those records, including link_to_user!, would fail.
    it "keeps existing members saveable after their role is retired from the configuration" do
      configure_roles("Security Champion")
      membership = create(:authorization_boundary_membership, authorization_boundary: boundary, role: "Security Champion")

      configure_roles("isso")

      expect(membership.reload.update(user_name: "Renamed Person")).to be(true)
      expect(membership.reload.role).to eq("security_champion")
    end

    it "still refuses to CHANGE a retired role to another invalid one" do
      configure_roles("Security Champion")
      membership = create(:authorization_boundary_membership, authorization_boundary: boundary, role: "Security Champion")

      configure_roles("isso")

      expect(membership.reload.update(role: "Something Else")).to be(false)
    end
  end

  describe "canonicalization on write" do
    it "stores the resolved value, not the spelling that was submitted" do
      membership = create(:authorization_boundary_membership, role: "ISSO")
      expect(membership.reload.role).to eq("isso")
    end

    it "leaves a persisted role untouched when other columns change" do
      membership = create(:authorization_boundary_membership, role: "isso")
      membership.update!(user_name: "Someone Else")
      expect(membership.reload.role).to eq("isso")
    end
  end

  describe "#role_label" do
    it "returns a human-readable label for the role" do
      membership = build(:authorization_boundary_membership, role: "authorizing_official")
      expect(membership.role_label).to eq("Authorizing Official (AO)")
    end

    it "returns ISSO label" do
      membership = build(:authorization_boundary_membership, role: "isso")
      expect(membership.role_label).to eq("ISSO")
    end

    it "titleizes a custom role with no configured label" do
      configure_roles("Security Champion")
      membership = build(:authorization_boundary_membership, role: "security_champion")
      expect(membership.role_label).to eq("Security Champion")
    end
  end

  # #875 — the "role:Label" pair form, matching SPARC_ENVIRONMENTS_LIST. Without
  # it, a custom role can only ever be displayed as titleize renders it.
  describe "role:Label pairs" do
    it "uses the configured label for a custom role" do
      configure_roles("3pao_lead:3PAO Lead")
      expect(described_class.available_roles).to eq(%w[3pao_lead])
      expect(described_class.role_label_for("3pao_lead")).to eq("3PAO Lead")
    end

    it "lets an operator relabel a built-in role without inventing a new one" do
      configure_roles("isso:Information System Security Officer")
      expect(described_class.available_roles).to eq(%w[isso])
      expect(described_class.role_label_for("isso")).to eq("Information System Security Officer")
    end

    it "falls back to the built-in label when no override is given" do
      configure_roles("isso")
      expect(described_class.role_label_for("isso")).to eq("ISSO")
    end

    it "renders the pair form in the dropdown options" do
      configure_roles("isso:Information System Security Officer,Security Champion")
      expect(described_class.role_options).to eq(
        [ [ "Information System Security Officer", "isso" ], [ "Security Champion", "security_champion" ] ]
      )
    end
  end
end
