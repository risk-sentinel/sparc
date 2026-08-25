# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Users", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:admin) { create(:user, :admin) }
  let(:regular_user) { create(:user) }

  def valid_params(overrides = {})
    {
      user: {
        email: "created@example.com",
        password: "SecurePassword123!",
        password_confirmation: "SecurePassword123!",
        first_name: "Created",
        last_name: "User",
        display_name: "Created User",
        status: "active"
      }.merge(overrides)
    }
  end

  describe "authorization" do
    it "redirects a non-admin away from the new form" do
      sign_in_as(regular_user)
      get new_admin_user_path
      expect(response).to redirect_to(root_path)
    end

    it "blocks a non-admin from creating a user" do
      sign_in_as(regular_user)
      expect {
        post admin_users_path, params: valid_params
      }.not_to change(User, :count)
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /admin/users/new" do
    before { sign_in_as(admin) }

    it "renders the create-user form" do
      get new_admin_user_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New User")
      expect(response.body).to include("Create User")
    end
  end

  describe "POST /admin/users" do
    before { sign_in_as(admin) }

    it "creates an active user and redirects to the show page" do
      expect {
        post admin_users_path, params: valid_params
      }.to change(User, :count).by(1)

      user = User.find_by(email: "created@example.com")
      expect(user).to be_present
      expect(user.status).to eq("active")
      expect(user.admin).to be(false)
      expect(response).to redirect_to(admin_user_path(user))
    end

    # #877 — provisioning now emits TWO events: the account was created, and a
    # credential was issued. They are distinct facts and both belong in the
    # trail (AU-2/AU-3) — folding the second into the first's metadata would
    # make "show me every time a credential was handed to a user" unqueryable,
    # which is precisely the question an assessor asks. assert_audit_event
    # requires a delta of exactly 1, so this asserts each event directly.
    it "emits a user_created audit event" do
      expect { post admin_users_path, params: valid_params }
        .to change(AuditEvent, :count).by(2)

      created = AuditEvent.find_by(action: "user_created", subject_type: "User")
      expect(created).to be_present
      expect(created.metadata["target_email"]).to eq("created@example.com")
    end

    it "also records that a credential was issued, with the same action a reset uses" do
      expect { post admin_users_path, params: valid_params }
        .to change { AuditEvent.where(action: "admin_temporary_password_issued").count }.by(1)

      event = AuditEvent.where(action: "admin_temporary_password_issued").order(:created_at).last
      expect(event.metadata["provisioning"]).to be(true)
    end

    it "lets an admin create another admin" do
      post admin_users_path, params: valid_params(admin: "1")
      expect(User.find_by(email: "created@example.com").admin).to be(true)
    end

    it "assigns selected instance roles" do
      role = create(:role, scope: "instance", display_name: "ISSO")
      post admin_users_path, params: valid_params(role_ids: [ role.id.to_s ])
      user = User.find_by(email: "created@example.com")
      expect(user.user_roles.where(authorization_boundary_id: nil).pluck(:role_id)).to include(role.id)
    end

    context "validation failures" do
      # #877 — this used to assert that a short admin-chosen password was
      # rejected. The admin no longer chooses one at all: :password is not a
      # permitted provisioning attribute, and SPARC issues a temporary that must
      # be replaced at first sign-in. So the property worth pinning is no longer
      # "a weak password is refused" but "a supplied password has no effect" —
      # which is stronger, because it cannot be satisfied by silently
      # overwriting the value and leaving the caller to assume otherwise.
      it "ignores a password supplied by the admin and issues its own" do
        expect {
          post admin_users_path, params: valid_params(password: "short", password_confirmation: "short")
        }.to change(User, :count).by(1)

        created = User.find_by(email: "created@example.com")
        expect(created.authenticate("short")).to be_falsey
        expect(created.must_reset_password).to be(true)
        expect(flash[:temporary_password]).to be_present
        expect(created.authenticate(flash[:temporary_password])).to be_truthy
      end

      it "rejects a duplicate email" do
        create(:user, email: "created@example.com")
        expect {
          post admin_users_path, params: valid_params
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  # #878 — deactivating or suspending the last active admin locks everyone out
  # of administration, and reactivation needs another admin, so there is no
  # self-service way back. The model refuses; these assert the admin is told,
  # and that the refusal reaches the audit trail rather than failing silently
  # (AuditEvent::ACTIONS is an allowlist — an unlisted action is dropped).
  describe "last-admin protection" do
    before { sign_in_as(admin) }

    it "refuses to deactivate the only active admin and says why" do
      expect { patch deactivate_admin_user_path(admin) }.not_to change { admin.reload.status }

      expect(admin.reload).to be_active
      expect(flash[:error]).to match(/only active administrator/)
    end

    it "records the refusal in the audit trail" do
      expect { patch deactivate_admin_user_path(admin) }
        .to change { AuditEvent.where(action: "user_deactivate_refused").count }.by(1)
    end

    it "refuses to suspend the only active admin — suspended cannot authenticate either" do
      expect { patch suspend_admin_user_path(admin) }.not_to change { admin.reload.status }

      expect(flash[:error]).to match(/only active administrator/)
    end

    it "records the suspend refusal too" do
      expect { patch suspend_admin_user_path(admin) }
        .to change { AuditEvent.where(action: "user_suspend_refused").count }.by(1)
    end

    it "allows deactivation once a second active admin exists" do
      other = create(:user, :admin, email: "second-admin@example.com")

      expect { patch deactivate_admin_user_path(other) }
        .to change { other.reload.status }.from("active").to("deactivated")
    end
  end
end
