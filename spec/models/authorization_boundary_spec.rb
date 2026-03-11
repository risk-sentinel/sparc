require "rails_helper"

RSpec.describe AuthorizationBoundary, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:status) }
  end

  describe "associations" do
    it { is_expected.to have_many(:boundaries).dependent(:destroy) }
    it { is_expected.to have_many(:authorization_boundary_memberships).dependent(:destroy) }
    it { is_expected.to have_one(:ssp_document).dependent(:nullify) }
    it { is_expected.to have_one(:sap_document).dependent(:nullify) }
    it { is_expected.to have_one(:sar_document).dependent(:nullify) }
    it { is_expected.to have_many(:poam_documents).dependent(:nullify) }
  end

  describe "enums" do
    it {
      is_expected.to define_enum_for(:status)
        .backed_by_column_of_type(:string)
        .with_values(draft: "draft", active: "active", authorized: "authorized", deauthorized: "deauthorized")
    }
  end

  describe "#artifact_summary" do
    it "returns a hash with artifact counts" do
      authorization_boundary = create(:authorization_boundary)
      summary = authorization_boundary.artifact_summary

      expect(summary).to include(:ssp, :sap, :sar, :poam_count, :boundary_count, :component_count)
      expect(summary[:poam_count]).to eq(0)
    end
  end

  describe "#members_by_role" do
    it "groups memberships by role" do
      authorization_boundary = create(:authorization_boundary, :with_members)
      grouped = authorization_boundary.members_by_role

      expect(grouped.keys).to include("system_owner", "isso")
    end
  end
end
