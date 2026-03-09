# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditCsvExportService do
  describe "#export" do
    it "generates CSV with correct headers" do
      AuditEvent.create!(action: "login_success", ip_address: "127.0.0.1", metadata: {})
      csv = described_class.new(AuditEvent.all).export
      lines = csv.split("\n")
      expect(lines.first).to eq("timestamp,user_email,action,category,subject_type,subject_id,ip_address,user_agent,metadata")
    end

    it "includes event data rows" do
      user = create(:user, email: "test@example.com")
      AuditEvent.log(user: user, action: "login_success", ip_address: "10.0.0.1")
      csv = described_class.new(AuditEvent.all).export
      expect(csv).to include("test@example.com")
      expect(csv).to include("login_success")
      expect(csv).to include("10.0.0.1")
    end

    it "shows (system) for events without users" do
      AuditEvent.create!(action: "login_failure", ip_address: "10.0.0.1", metadata: {})
      csv = described_class.new(AuditEvent.all).export
      expect(csv).to include("(system)")
    end

    it "includes subject info when present" do
      authorization_boundary = create(:authorization_boundary)
      AuditEvent.log(action: "authorization_boundary_created", ip_address: "127.0.0.1", subject: authorization_boundary)
      csv = described_class.new(AuditEvent.all).export
      expect(csv).to include("AuthorizationBoundary")
      expect(csv).to include(authorization_boundary.id.to_s)
    end

    it "generates valid CSV for empty scope" do
      csv = described_class.new(AuditEvent.none).export
      lines = csv.split("\n")
      expect(lines.count).to eq(1) # headers only
    end
  end
end
