require "rails_helper"

RSpec.describe Boundary, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:environment) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:authorization_boundary) }
    it { is_expected.to have_many(:boundary_cdef_documents).dependent(:destroy) }
    it { is_expected.to have_many(:cdef_documents).through(:boundary_cdef_documents) }
  end

  describe "environment (configurable set, #770)" do
    let(:authorization_boundary) { create(:authorization_boundary) }

    it "accepts a value in the configured set" do
      b = build(:boundary, authorization_boundary: authorization_boundary, environment: "user_acceptance_testing")
      expect(b).to be_valid
    end

    it "still accepts the legacy enum values (slugs round-trip)" do
      %w[production development staging test].each do |v|
        b = build(:boundary, authorization_boundary: authorization_boundary, environment: v)
        expect(b).to be_valid, "expected #{v.inspect} to remain valid"
      end
    end

    it "rejects a value outside the configured set on a new selection" do
      b = build(:boundary, authorization_boundary: authorization_boundary, environment: "not_a_real_env")
      expect(b).not_to be_valid
      expect(b.errors[:environment]).to include("is not one of the configured environments")
    end

    it "does not re-validate an already-persisted value when the config changes" do
      # A boundary saved under a broader list must stay editable after the list
      # narrows — the inclusion check only fires on an environment change.
      b = create(:boundary, authorization_boundary: authorization_boundary, environment: "staging")
      allow(SparcConfig).to receive(:environment_values).and_return(%w[production])
      b.name = "renamed"
      expect(b).to be_valid
    end

    it "renders a 'Name (CODE)' label" do
      b = build(:boundary, environment: "user_acceptance_testing")
      expect(b.environment_label).to eq("User Acceptance Testing (UAT)")
    end
  end
end
