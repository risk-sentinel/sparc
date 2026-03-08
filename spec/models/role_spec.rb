# frozen_string_literal: true

require "rails_helper"

RSpec.describe Role, type: :model do
  describe "validations" do
    subject { build(:role) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name) }
    it { is_expected.to validate_presence_of(:display_name) }
    it { is_expected.to validate_inclusion_of(:scope).in_array(%w[instance project]) }
  end

  describe "associations" do
    it { is_expected.to have_many(:user_roles).dependent(:destroy) }
    it { is_expected.to have_many(:users).through(:user_roles) }
  end

  describe "scopes" do
    let!(:instance_role) { create(:role, scope: "instance") }
    let!(:project_role) { create(:role, scope: "project") }

    it ".instance_scoped returns instance roles" do
      expect(Role.instance_scoped).to include(instance_role)
      expect(Role.instance_scoped).not_to include(project_role)
    end

    it ".project_scoped returns project roles" do
      expect(Role.project_scoped).to include(project_role)
      expect(Role.project_scoped).not_to include(instance_role)
    end
  end

  describe "#has_permission?" do
    let(:role) { create(:role, permissions: { "ssp.read" => true, "ssp.write" => false }) }

    it "returns true for granted permissions" do
      expect(role.has_permission?("ssp.read")).to be true
    end

    it "returns false for denied permissions" do
      expect(role.has_permission?("ssp.write")).to be false
    end

    it "returns false for unset permissions" do
      expect(role.has_permission?("sar.read")).to be false
    end
  end

  describe "#assign_permissions" do
    let(:role) { build(:role) }

    it "sets permissions from form params" do
      role.assign_permissions("ssp.read" => "1", "ssp.write" => "1", "sar.read" => "0")
      expect(role.permissions["ssp.read"]).to be true
      expect(role.permissions["ssp.write"]).to be true
      expect(role.permissions["sar.read"]).to be false
    end

    it "defaults unchecked permissions to false" do
      role.assign_permissions({})
      Role::PERMISSION_KEYS.each do |key|
        expect(role.permissions[key]).to be false
      end
    end
  end

  describe "PERMISSION_KEYS" do
    it "contains expected permission keys" do
      expect(Role::PERMISSION_KEYS).to include("ssp.read", "ssp.write", "catalogs.read")
    end

    it "groups permissions by resource" do
      expect(Role::PERMISSION_GROUPS.keys).to include("ssp", "catalogs", "projects")
    end
  end
end
