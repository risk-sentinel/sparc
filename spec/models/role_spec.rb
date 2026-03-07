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
end
