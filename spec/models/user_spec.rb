# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  subject { build(:user) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[active suspended deactivated]) }

    it "requires password to be at least 12 characters" do
      user = build(:user, password: "short", password_confirmation: "short")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("must be at least 12 characters (NIST 800-63B)")
    end

    it "allows nil password (for OAuth-only users)" do
      user = build(:user, :oauth_only)
      expect(user).to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to have_many(:identities).dependent(:destroy) }
    it { is_expected.to have_many(:user_roles).dependent(:destroy) }
    it { is_expected.to have_many(:roles).through(:user_roles) }
    it { is_expected.to have_many(:audit_events).dependent(:nullify) }
  end

  describe "#normalize_email" do
    it "downcases and strips email before validation" do
      user = create(:user, email: "  Jane.Doe@AOL.com  ")
      expect(user.email).to eq("jane.doe@aol.com")
    end

    it "prevents duplicate emails with different casing" do
      create(:user, email: "jane.doe@aol.com")
      duplicate = build(:user, email: "Jane.Doe@AOL.com")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include("has already been taken")
    end

    # #593 — DB-level enforcement: even when the app-layer validation and the
    # normalize_email callback are bypassed (raw insert, race condition), the
    # functional unique index on LOWER(email) must reject case-variant
    # duplicates. This closes the local-vs-OIDC casing workaround at the
    # database, not just the model.
    it "rejects case-variant duplicates at the database when validations are bypassed" do
      create(:user, email: "jane.doe@aol.com")
      collision = build(:user, email: "Jane.Doe@AOL.com")
      # skip normalize_email + uniqueness validation; go straight to INSERT
      allow(collision).to receive(:normalize_email)
      expect { collision.save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#active?" do
    it "returns true for active users" do
      expect(build(:user, status: "active")).to be_active
    end

    it "returns false for suspended users" do
      expect(build(:user, status: "suspended")).not_to be_active
    end
  end

  describe "#has_role?" do
    let(:user) { create(:user) }
    let(:role) { create(:role, name: "isso") }

    it "returns false when user has no roles" do
      expect(user.has_role?("isso")).to be false
    end

    it "returns true when user has the role" do
      create(:user_role, user: user, role: role)
      expect(user.has_role?("isso")).to be true
    end

    it "returns true for admins regardless of roles" do
      admin = create(:user, :admin)
      expect(admin.has_role?("isso")).to be true
    end
  end

  describe "#display_label" do
    it "returns display_name when present" do
      user = build(:user, display_name: "Jane Doe")
      expect(user.display_label).to eq("Jane Doe")
    end

    it "returns full name when display_name is blank" do
      user = build(:user, display_name: nil, first_name: "Jane", last_name: "Doe")
      expect(user.display_label).to eq("Jane Doe")
    end

    it "returns email when no name is set" do
      user = build(:user, display_name: nil, first_name: nil, last_name: nil, email: "jane@example.com")
      expect(user.display_label).to eq("jane@example.com")
    end
  end

  describe "#has_permission?" do
    let(:user) { create(:user) }
    let(:role) { create(:role, permissions: { "ssp.read" => true, "ssp.write" => true }) }

    it "returns true when user has a role with the permission" do
      create(:user_role, user: user, role: role)
      expect(user.has_permission?("ssp.read")).to be true
    end

    it "returns false when user has no matching permission" do
      create(:user_role, user: user, role: role)
      expect(user.has_permission?("sar.write")).to be false
    end

    it "returns true for admins regardless of permissions" do
      admin = create(:user, :admin)
      expect(admin.has_permission?("ssp.read")).to be true
    end

    context "with authorization boundary scope" do
      let(:authorization_boundary) { create(:authorization_boundary) }
      let(:boundary_role) { create(:role, :authorization_boundary_scoped, permissions: { "ssp.write" => true }) }

      it "checks authorization-boundary-scoped roles" do
        create(:user_role, user: user, role: boundary_role, authorization_boundary: authorization_boundary)
        expect(user.has_permission?("ssp.write", authorization_boundary_id: authorization_boundary.id)).to be true
      end

      it "does not leak authorization boundary permissions to other authorization boundaries" do
        other_authorization_boundary = create(:authorization_boundary)
        create(:user_role, user: user, role: boundary_role, authorization_boundary: authorization_boundary)
        expect(user.has_permission?("ssp.write", authorization_boundary_id: other_authorization_boundary.id)).to be false
      end
    end
  end

  describe "#record_sign_in!" do
    it "increments sign_in_count and sets last_sign_in_at" do
      user = create(:user, sign_in_count: 0)
      user.record_sign_in!(ip_address: "192.168.1.1")
      user.reload
      expect(user.sign_in_count).to eq(1)
      expect(user.last_sign_in_at).to be_present
      expect(user.last_sign_in_ip).to eq("192.168.1.1")
    end

    it "still bumps updated_at, as the update! it replaced did" do
      user = create(:user)
      user.update_columns(updated_at: 3.days.ago)

      expect { user.record_sign_in!(ip_address: "10.0.0.1") }
        .to(change { user.reload.updated_at })
    end

    # #857 — sign-in used to save the whole record, so EVERY validation had to
    # pass for a login to succeed. The avatar rule is how this was found, but
    # the coupling is the defect: a record invalid for a reason that has nothing
    # to do with authentication must still be able to sign in.
    #
    # The example uses a service account whose owner has been nullified —
    # ordinary data drift, and exactly the kind of record the API token bridge
    # signs in. The avatar is no longer usable to demonstrate this because #892
    # stopped the avatar rule from firing on unrelated saves at all.
    context "when the record is invalid for an unrelated reason" do
      let(:user) do
        create(:user, sign_in_count: 0).tap do |u|
          u.update_columns(service_account: true, owner_id: nil)
          u.reload
        end
      end

      it "the record really is invalid — the precondition this rests on" do
        expect(user).not_to be_valid
        expect(user.errors[:owner_id].join).to match(/required for service accounts/)
      end

      it "records the sign-in anyway" do
        expect { user.record_sign_in!(ip_address: "192.168.1.1") }.not_to raise_error

        user.reload
        expect(user.sign_in_count).to eq(1)
        expect(user.last_sign_in_ip).to eq("192.168.1.1")
        expect(user.last_sign_in_at).to be_present
      end

      it "does not quietly repair the record to get there" do
        user.record_sign_in!(ip_address: "192.168.1.1")

        expect(user.reload.owner_id).to be_nil
        expect(user).not_to be_valid
      end
    end
  end

  # #892 — the avatar validator used to run on EVERY save of a user who had an
  # avatar, re-reading the blob out of storage to check something the save was
  # not changing, and at upload time it did not actually run (the blob is not in
  # the service yet, so its rescue fired). Both halves are fixed by validating
  # the attachable being attached.
  describe "avatar validation (#892)" do
    let(:user) { create(:user) }
    let(:real_image) { Rails.root.join("app/assets/images/sparc_admin.jpg") }

    def attach_image(target, path)
      target.avatar.attach(io: File.open(path), filename: File.basename(path),
                           content_type: "image/jpeg")
    end

    describe "at attach time" do
      it "refuses a non-image, on the console/API path with no controller involved" do
        result = user.avatar.attach(
          io: StringIO.new("definitely not an image"),
          filename: "avatar.png",
          content_type: "image/png" # a lie; the bytes are what count (#509)
        )

        expect(result).to be_falsey
        expect(user.reload.avatar).not_to be_attached
        expect(user.errors[:avatar].join).to match(/must be a PNG, JPG, GIF, or WebP image/)
      end

      it "accepts a real image" do
        skip "fixture image missing" unless File.exist?(real_image)

        expect(attach_image(user, real_image)).to be_truthy
        expect(user.reload.avatar).to be_attached
      end

      it "uploads the file intact — the sniff rewinds what it reads" do
        skip "fixture image missing" unless File.exist?(real_image)
        attach_image(user, real_image)

        expect(user.reload.avatar.blob.byte_size).to eq(File.size(real_image))
      end
    end

    # The lockout, at its source. A stored avatar that no longer satisfies the
    # rule — because the rule was tightened, or the file arrived by seed, import
    # or restore — must not make the account unmanageable.
    describe "when a stored avatar would no longer pass a tightened rule" do
      let(:tightened) { %w[image/gif] } # jpeg no longer accepted

      before do
        skip "fixture image missing" unless File.exist?(real_image)
        attach_image(user, real_image)
        user.reload
        stub_const("User::ALLOWED_AVATAR_MIME_TYPES", tightened)
      end

      it "the record is still valid — unrelated saves do not re-check the stored blob" do
        expect(user).to be_valid
      end

      it "an administrator can still deactivate the account" do
        expect { user.deactivate!(reason: "admin_action") }.not_to raise_error
        expect(user.reload.status).to eq("deactivated")
      end

      it "can still be reactivated" do
        user.deactivate!(reason: "admin_action")
        expect { user.reactivate! }.not_to raise_error
        expect(user.reload.status).to eq("active")
      end

      it "can still be issued a temporary password" do
        expect { user.issue_temporary_password! }.not_to raise_error
      end

      it "can still have unrelated attributes updated" do
        expect { user.update!(first_name: "Renamed") }.not_to raise_error
      end
    end
  end
end
