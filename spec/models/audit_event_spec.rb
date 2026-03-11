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

  describe "ACTIONS" do
    it "includes auth actions" do
      expect(AuditEvent::ACTIONS).to include("login_success", "login_failure", "logout", "password_change")
    end

    it "includes resource CRUD actions" do
      expect(AuditEvent::ACTIONS).to include(
        "ssp_document_created", "ssp_document_updated", "ssp_document_deleted", "ssp_document_exported",
        "sar_document_created", "control_catalog_imported", "control_mapping_published"
      )
    end

    it "includes authorization_failure" do
      expect(AuditEvent::ACTIONS).to include("authorization_failure")
    end
  end

  describe "ACTION_CATEGORIES" do
    it "covers all actions" do
      categorized = AuditEvent::ACTION_CATEGORIES.values.flatten
      uncategorized = AuditEvent::ACTIONS - categorized
      expect(uncategorized).to be_empty,
        "These actions are not in any category: #{uncategorized.join(', ')}"
    end

    it "has no orphan actions in categories" do
      categorized = AuditEvent::ACTION_CATEGORIES.values.flatten
      orphans = categorized - AuditEvent::ACTIONS
      expect(orphans).to be_empty,
        "These category actions are not in ACTIONS: #{orphans.join(', ')}"
    end
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

    it "stores subject_type and subject_id when subject is provided" do
      # Create an actual record to use as subject
      authorization_boundary = create(:authorization_boundary)
      event = AuditEvent.log(
        user: user, action: "authorization_boundary_created",
        ip_address: "127.0.0.1", subject: authorization_boundary
      )
      expect(event.subject_type).to eq("AuthorizationBoundary")
      expect(event.subject_id).to eq(authorization_boundary.id)
    end

    it "leaves subject columns nil when no subject provided" do
      event = AuditEvent.log(user: user, action: "login_success", ip_address: "127.0.0.1")
      expect(event.subject_type).to be_nil
      expect(event.subject_id).to be_nil
    end

    it "emits structured JSON to Rails logger" do
      allow(Rails.logger).to receive(:info)

      AuditEvent.log(user: user, action: "login_success", ip_address: "10.0.0.1")

      expect(Rails.logger).to have_received(:info).with(a_string_including('"audit_event"'))
      expect(Rails.logger).to have_received(:info).with(a_string_including('"action":"login_success"'))
      expect(Rails.logger).to have_received(:info).with(a_string_including('"ip_address":"10.0.0.1"'))
      expect(Rails.logger).to have_received(:info).with(a_string_including(user.email))
    end

    it "includes subject info in structured log when subject provided" do
      allow(Rails.logger).to receive(:info)
      authorization_boundary = create(:authorization_boundary)

      AuditEvent.log(user: user, action: "authorization_boundary_created", ip_address: "10.0.0.1", subject: authorization_boundary)

      expect(Rails.logger).to have_received(:info).with(a_string_including('"subject_type":"AuthorizationBoundary"'))
      expect(Rails.logger).to have_received(:info).with(a_string_including("\"subject_id\":#{authorization_boundary.id}"))
    end
  end

  describe "#category" do
    it "returns Authentication for login events" do
      event = build(:audit_event, action: "login_success")
      expect(event.category).to eq("Authentication")
    end

    it "returns SSP Documents for ssp events" do
      event = build(:audit_event, action: "ssp_document_created")
      expect(event.category).to eq("SSP Documents")
    end

    it "returns Authorization for authorization_failure" do
      event = build(:audit_event, action: "authorization_failure")
      expect(event.category).to eq("Authorization")
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }

    describe ".for_subject" do
      it "returns events for a specific subject" do
        authorization_boundary = create(:authorization_boundary)
        AuditEvent.log(user: user, action: "authorization_boundary_created", ip_address: "127.0.0.1", subject: authorization_boundary)
        AuditEvent.log(user: user, action: "login_success", ip_address: "127.0.0.1")

        results = AuditEvent.for_subject(authorization_boundary)
        expect(results.count).to eq(1)
        expect(results.first.action).to eq("authorization_boundary_created")
      end
    end

    describe ".by_subject_type" do
      it "filters by subject type string" do
        AuditEvent.create!(action: "ssp_document_created", subject_type: "SspDocument", subject_id: 1, metadata: {})
        AuditEvent.create!(action: "authorization_boundary_created", subject_type: "AuthorizationBoundary", subject_id: 1, metadata: {})

        results = AuditEvent.by_subject_type("SspDocument")
        expect(results.count).to eq(1)
      end
    end

    describe ".by_category" do
      it "filters by category name" do
        AuditEvent.create!(action: "login_success", metadata: {})
        AuditEvent.create!(action: "ssp_document_created", metadata: {})

        results = AuditEvent.by_category("Authentication")
        expect(results.count).to eq(1)
        expect(results.first.action).to eq("login_success")
      end

      it "returns none for unknown category" do
        expect(AuditEvent.by_category("Nonexistent")).to be_empty
      end
    end

    describe ".in_date_range" do
      it "filters events by date range" do
        old_event = AuditEvent.create!(action: "login_success", created_at: 30.days.ago, metadata: {})
        new_event = AuditEvent.create!(action: "login_success", created_at: 1.day.ago, metadata: {})

        results = AuditEvent.in_date_range(7.days.ago.to_date, Date.today)
        expect(results).to include(new_event)
        expect(results).not_to include(old_event)
      end

      it "handles nil start_date by applying only end_date filter" do
        event = AuditEvent.create!(action: "login_success", created_at: 1.day.ago, metadata: {})
        results = AuditEvent.in_date_range(nil, Date.today)
        expect(results).to include(event)
      end
    end

    describe ".search" do
      it "searches in action name" do
        AuditEvent.create!(action: "login_success", metadata: {})
        AuditEvent.create!(action: "ssp_document_created", metadata: {})

        results = AuditEvent.search("login")
        expect(results.count).to eq(1)
      end

      it "searches in metadata" do
        AuditEvent.create!(action: "ssp_document_created", metadata: { name: "My Test SSP" })
        AuditEvent.create!(action: "login_success", metadata: {})

        results = AuditEvent.search("My Test SSP")
        expect(results.count).to eq(1)
      end

      it "returns all for blank query" do
        AuditEvent.create!(action: "login_success", metadata: {})
        expect(AuditEvent.search("").count).to eq(1)
        expect(AuditEvent.search(nil).count).to eq(1)
      end
    end
  end
end
