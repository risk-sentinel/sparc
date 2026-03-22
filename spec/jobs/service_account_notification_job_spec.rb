# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceAccountNotificationJob, type: :job do
  let(:owner) { create(:user, email: "owner@sparc.local") }

  before do
    allow(SparcConfig).to receive(:enable_smtp?).and_return(true)
    allow(SparcConfig).to receive(:smtp_from_address).and_return("noreply@sparc.test")
    allow(SparcConfig).to receive(:app_host).and_return("sparc.test")
    allow(SparcConfig).to receive(:sa_inactivity_days).and_return(90)
  end

  def create_sa_with_token(expires_at: nil, last_used_at: nil)
    sa = create(:user, service_account: true, owner: owner, status: "active")
    token = ApiToken.generate!(user: sa, name: "test-token", expires_at: expires_at)
    token.update_columns(last_used_at: last_used_at) if last_used_at
    sa
  end

  describe "#perform" do
    it "skips entirely when SMTP is disabled" do
      allow(SparcConfig).to receive(:enable_smtp?).and_return(false)
      create_sa_with_token(expires_at: 3.days.from_now)
      expect { described_class.perform_now }
        .not_to have_enqueued_mail(ServiceAccountMailer, :token_expiry_urgent)
    end

    context "token expiry warning (8-14 days)" do
      it "sends warning for token expiring in 10 days" do
        create_sa_with_token(expires_at: 10.days.from_now)
        expect { described_class.perform_now }
          .to have_enqueued_mail(ServiceAccountMailer, :token_expiry_warning)
      end

      it "does not send warning for token expiring in 20 days" do
        create_sa_with_token(expires_at: 20.days.from_now)
        expect { described_class.perform_now }
          .not_to have_enqueued_mail(ServiceAccountMailer, :token_expiry_warning)
      end
    end

    context "token expiry urgent (1-7 days)" do
      it "sends urgent for token expiring in 3 days" do
        create_sa_with_token(expires_at: 3.days.from_now)
        expect { described_class.perform_now }
          .to have_enqueued_mail(ServiceAccountMailer, :token_expiry_urgent)
      end

      it "does not send urgent for token expiring in 10 days" do
        create_sa_with_token(expires_at: 10.days.from_now)
        expect { described_class.perform_now }
          .not_to have_enqueued_mail(ServiceAccountMailer, :token_expiry_urgent)
      end
    end

    context "expired notices" do
      it "sends notice for account disabled today due to token_expired" do
        sa = create(:user,
          service_account: true,
          owner: owner,
          status: "suspended",
          disabled_at: Time.current,
          disabled_reason: "token_expired")

        expect { described_class.perform_now }
          .to have_enqueued_mail(ServiceAccountMailer, :token_expired_notice)
      end

      it "does not send notice for account disabled yesterday" do
        sa = create(:user,
          service_account: true,
          owner: owner,
          status: "suspended",
          disabled_at: 2.days.ago,
          disabled_reason: "token_expired")

        expect { described_class.perform_now }
          .not_to have_enqueued_mail(ServiceAccountMailer, :token_expired_notice)
      end
    end

    context "inactivity warnings" do
      it "sends warning when account is within 7 days of threshold" do
        create_sa_with_token(last_used_at: 85.days.ago, expires_at: 1.year.from_now)
        expect { described_class.perform_now }
          .to have_enqueued_mail(ServiceAccountMailer, :inactivity_warning)
      end

      it "does not send warning when account was used recently" do
        create_sa_with_token(last_used_at: 10.days.ago, expires_at: 1.year.from_now)
        expect { described_class.perform_now }
          .not_to have_enqueued_mail(ServiceAccountMailer, :inactivity_warning)
      end
    end
  end
end
