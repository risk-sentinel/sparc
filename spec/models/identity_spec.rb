# frozen_string_literal: true

require "rails_helper"

RSpec.describe Identity, type: :model do
  describe "validations" do
    subject { build(:identity) }

    it { is_expected.to validate_presence_of(:provider) }
    it { is_expected.to validate_presence_of(:uid) }
    it { is_expected.to validate_uniqueness_of(:uid).scoped_to(:provider) }
    it { is_expected.to validate_inclusion_of(:provider).in_array(%w[github gitlab oidc ldap]) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
  end

  describe ".from_omniauth" do
    let(:auth) do
      OmniAuth::AuthHash.new(
        provider: "github",
        uid: "12345",
        info: OmniAuth::AuthHash::InfoHash.new(
          email: "jane@example.com",
          name: "Jane Doe"
        )
      )
    end

    it "initializes a new identity from auth hash" do
      identity = Identity.from_omniauth(auth)
      expect(identity.provider).to eq("github")
      expect(identity.uid).to eq("12345")
      expect(identity.email).to eq("jane@example.com")
    end

    it "finds existing identity by provider and uid" do
      user = create(:user)
      existing = create(:identity, user: user, provider: "github", uid: "12345")
      identity = Identity.from_omniauth(auth)
      expect(identity).to eq(existing)
    end
  end
end
