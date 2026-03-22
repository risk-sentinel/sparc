# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceAccountMailer, type: :mailer do
  let(:owner) { create(:user, email: "owner@sparc.local", admin: false) }
  let(:admin) { create(:user, email: "admin@sparc.local", admin: true) }
  let(:service_account) do
    create(:user,
      first_name: "sparc-iac",
      email: "sparc-iac@service.local",
      service_account: true,
      owner: owner)
  end

  before do
    admin # ensure admin exists
    allow(SparcConfig).to receive(:enable_smtp?).and_return(true)
    allow(SparcConfig).to receive(:smtp_from_address).and_return("noreply@sparc.test")
    allow(SparcConfig).to receive(:app_host).and_return("sparc.test")
  end

  describe "#token_expiry_warning" do
    let(:mail) { described_class.token_expiry_warning(service_account, days_remaining: 14) }

    it "sends to owner only" do
      expect(mail.to).to eq([ owner.email ])
    end

    it "includes account name in subject" do
      expect(mail.subject).to include("sparc-iac")
      expect(mail.subject).to include("14 days")
    end

    it "does not build a message when SMTP disabled" do
      allow(SparcConfig).to receive(:enable_smtp?).and_return(false)
      mail = described_class.token_expiry_warning(service_account, days_remaining: 14)
      expect(mail.message).to be_a(ActionMailer::Base::NullMail)
    end
  end

  describe "#token_expiry_urgent" do
    let(:mail) { described_class.token_expiry_urgent(service_account, days_remaining: 7) }

    it "sends to owner and admins" do
      expect(mail.to).to include(owner.email)
      expect(mail.to).to include(admin.email)
    end

    it "includes URGENT in subject" do
      expect(mail.subject).to include("URGENT")
      expect(mail.subject).to include("7 days")
    end
  end

  describe "#token_expired_notice" do
    let(:mail) { described_class.token_expired_notice(service_account) }

    it "sends to owner and admins" do
      expect(mail.to).to include(owner.email)
      expect(mail.to).to include(admin.email)
    end

    it "includes disabled in subject" do
      expect(mail.subject).to include("disabled")
      expect(mail.subject).to include("expired")
    end
  end

  describe "#inactivity_warning" do
    let(:mail) { described_class.inactivity_warning(service_account, inactive_days: 83) }

    before do
      allow(SparcConfig).to receive(:sa_inactivity_days).and_return(90)
    end

    it "sends to owner only" do
      expect(mail.to).to eq([ owner.email ])
    end

    it "includes inactive days in subject" do
      expect(mail.subject).to include("83 days")
    end
  end
end
