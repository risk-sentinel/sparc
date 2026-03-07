# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditEvent, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:action) }
    it { is_expected.to validate_inclusion_of(:action).in_array(AuditEvent::ACTIONS) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:user).optional }
  end

  describe ".log" do
    let(:user) { create(:user) }

    it "creates an audit event" do
      expect {
        AuditEvent.log(user: user, action: "login_success", provider: "local", ip_address: "127.0.0.1")
      }.to change(AuditEvent, :count).by(1)
    end

    it "creates an event without a user (failed login)" do
      expect {
        AuditEvent.log(action: "login_failure", provider: "local", ip_address: "127.0.0.1")
      }.to change(AuditEvent, :count).by(1)

      event = AuditEvent.last
      expect(event.user).to be_nil
    end

    it "handles invalid action gracefully" do
      expect {
        AuditEvent.log(action: "invalid_action", provider: "local")
      }.not_to change(AuditEvent, :count)
    end
  end
end
