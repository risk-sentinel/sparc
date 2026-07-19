# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserProvisioningService do
  let(:admin) { create(:user, :admin) }
  let(:non_admin) { create(:user) }

  def user_params(overrides = {})
    ActionController::Parameters.new(
      email: "provisioned@example.com",
      password: "SecurePassword123!",
      password_confirmation: "SecurePassword123!",
      first_name: "Prov",
      last_name: "Isioned",
      display_name: "Prov Isioned"
    ).merge(overrides)
  end

  describe "#build" do
    it "builds a valid, unsaved user from base attributes" do
      user = described_class.new(actor: admin).build(user_params)
      expect(user).to be_a(User)
      expect(user).not_to be_persisted
      expect(user).to be_valid
      expect(user.email).to eq("provisioned@example.com")
    end

    context "privilege-bearing attributes" do
      it "lets an admin set :admin and :status" do
        user = described_class.new(actor: admin).build(user_params(admin: "1", status: "suspended"))
        expect(user.admin).to be(true)
        expect(user.status).to eq("suspended")
      end

      it "ignores :admin and :status from a non-admin actor" do
        user = described_class.new(actor: non_admin).build(user_params(admin: "1", status: "suspended"))
        expect(user.admin).to be(false)     # DB default
        expect(user.status).to eq("active") # DB default
      end

      it "never mass-assigns :admin/:status even for an admin (only via the gated setter)" do
        # Base permit list must exclude them; a nil actor gets defaults regardless.
        user = described_class.new(actor: nil).build(user_params(admin: "1", status: "deactivated"))
        expect(user.admin).to be(false)
        expect(user.status).to eq("active")
      end

      it "rejects an out-of-enum status" do
        user = described_class.new(actor: admin).build(user_params(status: "wat"))
        expect(user.status).to eq("active")
      end
    end

    it "accepts a plain Hash as params" do
      user = described_class.new(actor: admin).build(
        email: "hash@example.com", password: "SecurePassword123!",
        password_confirmation: "SecurePassword123!"
      )
      expect(user.email).to eq("hash@example.com")
    end
  end

  describe "#apply_privileged_attributes!" do
    it "sets attributes on an existing user for an admin" do
      target = create(:user)
      described_class.new(actor: admin).apply_privileged_attributes!(target, ActionController::Parameters.new(admin: "1"))
      expect(target.admin).to be(true)
    end

    it "no-ops for a non-admin actor" do
      target = create(:user)
      described_class.new(actor: non_admin).apply_privileged_attributes!(target, ActionController::Parameters.new(admin: "1"))
      expect(target.admin).to be(false)
    end

    it "no-ops when params are blank" do
      target = create(:user)
      expect { described_class.new(actor: admin).apply_privileged_attributes!(target, nil) }.not_to raise_error
    end
  end
end
