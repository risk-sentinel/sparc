# frozen_string_literal: true

require "rails_helper"

# #860 — the offboarding mechanism.
#
# Owner-decided: entitlements are established at login, and a user who stops
# logging in is deactivated after a configured number of days. That single
# signal covers a leaver, an IdP-disabled account and a dormant local login
# without SPARC needing to be told anything by the directory.
RSpec.describe DeactivateInactiveUsersJob do
  subject(:job) { described_class.new }

  describe "when SPARC_USER_INACTIVITY_DAYS is unset" do
    it "does nothing at all, so an upgrade never deactivates anyone" do
      allow(SparcConfig).to receive(:user_inactivity_days).and_return(0)
      stale = create(:user, last_sign_in_at: 2.years.ago)

      job.perform

      expect(stale.reload).to be_active
    end
  end

  context "with a 90 day threshold" do
    before { allow(SparcConfig).to receive(:user_inactivity_days).and_return(90) }

    # An admin exists throughout so the last-active-admin guard is not what is
    # under test in the ordinary examples.
    let!(:keeper_admin) { create(:user, :admin, last_sign_in_at: 1.day.ago) }

    it "deactivates a user past the threshold, with the reason recorded" do
      stale = create(:user, last_sign_in_at: 91.days.ago)

      job.perform

      expect(stale.reload).to be_deactivated
      expect(stale.inactive_reason).to eq("inactivity")
    end

    it "leaves a user inside the threshold alone" do
      recent = create(:user, last_sign_in_at: 89.days.ago)

      job.perform

      expect(recent.reload).to be_active
    end

    it "measures a user who has NEVER signed in from their creation date" do
      # Otherwise an account provisioned and then abandoned stays active
      # forever, which is the stale-account risk the control exists for.
      never = create(:user, last_sign_in_at: nil, created_at: 100.days.ago)

      job.perform

      expect(never.reload).to be_deactivated
    end

    it "does not deactivate a newly created account that has not signed in yet" do
      fresh = create(:user, last_sign_in_at: nil, created_at: 2.days.ago)

      job.perform

      expect(fresh.reload).to be_active
    end

    it "records an audit event naming the threshold" do
      stale = create(:user, last_sign_in_at: 91.days.ago)

      expect { job.perform }.to change {
        AuditEvent.where(action: "user_deactivated_for_inactivity").count
      }.by(1)

      event = AuditEvent.where(action: "user_deactivated_for_inactivity").last
      expect(event.user_id).to eq(stale.id)
      expect(event.metadata["inactivity_days"]).to eq(90)
    end

    it "registers the audit action, or it would record nowhere" do
      # A key missing from AuditEvent::ACTIONS writes no row and raises no
      # error — the #982 shape.
      expect(AuditEvent::ACTIONS).to include("user_deactivated_for_inactivity")
    end

    describe "service accounts" do
      it "are excluded, because they authenticate by token and never sign in" do
        # Including them would deactivate every service account on the first
        # run: last_sign_in_at is nil for all of them.
        robot = create(:user, :service_account, last_sign_in_at: nil, created_at: 2.years.ago)

        job.perform

        expect(robot.reload).to be_active
      end
    end

    describe "the instance must stay administrable" do
      it "never deactivates the last active admin, and says why" do
        keeper_admin.update!(last_sign_in_at: 200.days.ago)

        result = job.perform

        expect(keeper_admin.reload).to be_active
        expect(result[:skipped].map { |s| s[:email] }).to include(keeper_admin.email)
      end

      it "still deactivates an idle admin when another active admin remains" do
        create(:user, :admin, last_sign_in_at: 1.day.ago)
        keeper_admin.update!(last_sign_in_at: 200.days.ago)

        job.perform

        expect(keeper_admin.reload).to be_deactivated
      end
    end

    it "processes the rest when one user cannot be deactivated" do
      keeper_admin.update!(last_sign_in_at: 200.days.ago)
      stale = create(:user, last_sign_in_at: 120.days.ago)

      job.perform

      expect(stale.reload).to be_deactivated
      expect(keeper_admin.reload).to be_active
    end
  end
end
