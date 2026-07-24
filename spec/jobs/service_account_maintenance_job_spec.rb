# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceAccountMaintenanceJob, type: :job do
  let(:admin) { create(:user, :admin) }

  def create_service_account(name:, token_expires_at: nil, last_used_at: nil, created_at: nil)
    pw = SecureRandom.hex(16)
    sa = User.create!(
      email: "#{name}@service.local",
      first_name: name,
      last_name: "Pipeline",
      service_account: true,
      owner_id: admin.id,
      password: pw,
      password_confirmation: pw,
      status: "active"
    )
    sa.update_column(:created_at, created_at) if created_at

    token = ApiToken.generate!(user: sa, name: "#{name}-token", expires_at: token_expires_at)
    token.update_column(:last_used_at, last_used_at) if last_used_at
    sa
  end

  describe "#perform" do
    context "token expiry" do
      it "disables SA when all tokens are expired" do
        sa = create_service_account(name: "expired-sa", token_expires_at: 1.day.ago)

        expect { described_class.perform_now }
          .to change { sa.reload.status }.from("active").to("suspended")

        expect(sa.disabled_reason).to eq("token_expired")
      end

      it "does NOT disable SA with a non-expired token" do
        sa = create_service_account(name: "valid-sa", token_expires_at: 30.days.from_now)

        described_class.perform_now

        expect(sa.reload.status).to eq("active")
      end

      it "does NOT disable SA with a token that has no expiry" do
        sa = create_service_account(name: "no-expiry-sa", token_expires_at: nil)

        described_class.perform_now

        expect(sa.reload.status).to eq("active")
      end

      it "does NOT disable SA with no tokens" do
        pw = SecureRandom.hex(16)
        sa = User.create!(
          email: "no-tokens@service.local",
          first_name: "no-tokens", last_name: "Pipeline",
          service_account: true, owner_id: admin.id,
          password: pw, password_confirmation: pw, status: "active"
        )

        described_class.perform_now

        expect(sa.reload.status).to eq("active")
      end

      it "does NOT disable SA with mixed tokens (one expired, one active)" do
        sa = create_service_account(name: "mixed-sa", token_expires_at: 1.day.ago)
        ApiToken.generate!(user: sa, name: "active-token", expires_at: 30.days.from_now)

        described_class.perform_now

        expect(sa.reload.status).to eq("active")
      end
    end

    context "inactivity" do
      it "disables SA unused past threshold" do
        sa = create_service_account(
          name: "inactive-sa",
          token_expires_at: 1.year.from_now,
          last_used_at: 91.days.ago
        )

        described_class.perform_now

        expect(sa.reload.status).to eq("suspended")
        expect(sa.disabled_reason).to eq("inactivity")
      end

      it "does NOT disable SA used within threshold" do
        # #785 Pass 2.1 — the SA inactivity window is now the unified
        # SPARC_INACTIVITY_DAYS (default 30), not the old 90. 10 days ago is
        # comfortably within it; 30.days.ago would now sit on the boundary.
        sa = create_service_account(
          name: "active-sa",
          token_expires_at: 1.year.from_now,
          last_used_at: 10.days.ago
        )

        described_class.perform_now

        expect(sa.reload.status).to eq("active")
      end

      it "uses created_at as baseline for never-used accounts" do
        sa = create_service_account(
          name: "never-used-sa",
          token_expires_at: 1.year.from_now,
          created_at: 91.days.ago
        )

        described_class.perform_now

        expect(sa.reload.status).to eq("suspended")
        expect(sa.disabled_reason).to eq("inactivity")
      end

      it "does NOT disable recently created never-used accounts" do
        sa = create_service_account(
          name: "new-sa",
          token_expires_at: 1.year.from_now
        )

        described_class.perform_now

        expect(sa.reload.status).to eq("active")
      end
    end

    context "already disabled" do
      it "does NOT process already-disabled SAs" do
        sa = create_service_account(name: "disabled-sa", token_expires_at: 1.day.ago)
        sa.disable!(reason: "admin_action")

        expect { described_class.perform_now }
          .not_to change { sa.reload.disabled_at }
      end
    end

    context "audit events" do
      it "creates audit event for expired token disable" do
        create_service_account(name: "audit-expired", token_expires_at: 1.day.ago)

        expect { described_class.perform_now }
          .to change(AuditEvent, :count).by_at_least(1)

        event = AuditEvent.where(action: "service_account_auto_disabled").last
        expect(event.metadata["reason"]).to eq("token_expired")
        expect(event.user_id).to be_nil # system action
      end

      it "creates audit event for inactivity disable" do
        create_service_account(
          name: "audit-inactive",
          token_expires_at: 1.year.from_now,
          last_used_at: 91.days.ago
        )

        expect { described_class.perform_now }
          .to change(AuditEvent, :count).by_at_least(1)

        event = AuditEvent.where(action: "service_account_auto_disabled").last
        expect(event.metadata["reason"]).to eq("inactivity")
      end
    end
  end
end
