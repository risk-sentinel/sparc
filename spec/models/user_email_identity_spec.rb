# frozen_string_literal: true

require "rails_helper"

# #1176 (owner, option A) — a person's email identifies them; a service
# account's email is a contact and may repeat.
RSpec.describe User, "email identity (#1176)" do
  let(:owner) { create(:user) }

  def service_account(email)
    create(:user, :service_account, owner: owner, email: email)
  end

  describe "uniqueness" do
    it "lets one team mailbox own several service accounts" do
      first = service_account("platform-team@example.com")
      second = service_account("Platform-Team@example.com")

      expect([ first, second ]).to all(be_persisted)
    end

    it "lets a service account carry a person's email" do
      person = create(:user, email: "jane@example.com")

      expect(service_account("jane@example.com")).to be_persisted
      expect(person.reload).to be_valid
    end

    it "still refuses a second person with the same email, in any case" do
      create(:user, email: "jane@example.com")
      twin = build(:user, email: "JANE@example.com")

      expect(twin).not_to be_valid
      expect(twin.errors[:email]).to include("has already been taken")
    end

    it "lets a person take an email a service account already uses" do
      service_account("ops@example.com")

      expect(create(:user, email: "ops@example.com")).to be_persisted
    end

    it "is enforced by the database for people, past the model's validation" do
      create(:user, email: "dup@example.com")
      twin = build(:user, email: "DUP@example.com")

      expect { twin.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "is not enforced by the database for service accounts" do
      service_account("bot@example.com")
      second = build(:user, :service_account, owner: owner, email: "bot@example.com")

      expect { second.save!(validate: false) }.not_to raise_error
    end
  end

  describe ".human_by_email" do
    it "finds the person, case-insensitively, and never a service account sharing the email" do
      service_account("shared@example.com")
      person = create(:user, email: "shared@example.com")
      service_account("shared@example.com")

      expect(described_class.human_by_email(" SHARED@example.com ")).to eq(person)
    end

    it "finds nothing when only service accounts carry the email" do
      service_account("only-bots@example.com")

      expect(described_class.human_by_email("only-bots@example.com")).to be_nil
    end

    it "finds nothing for a blank email" do
      expect(described_class.human_by_email(nil)).to be_nil
      expect(described_class.human_by_email("")).to be_nil
    end
  end
end
