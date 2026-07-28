# REST API for User management.
#
# All endpoints require Bearer token authentication.
# Admin-only unless accessing own record.
#
# GET    /api/v1/users          — list (admin only, paginated)
# GET    /api/v1/users/:id      — show (admin or self)
# POST   /api/v1/users          — create (admin only)
# PATCH  /api/v1/users/:id      — update (admin or self, limited)
# DELETE /api/v1/users/:id      — deactivate (admin only)
# POST   /api/v1/users/:id/password_reset — issue a one-time reset link (admin only, #841)
#
class Api::V1::UsersController < Api::V1::BaseController
  before_action :set_user, only: [ :show, :update, :destroy ]
  before_action :authorize_admin_or_self!, only: [ :show, :update ]
  before_action :authorize_admin!, only: [ :index, :create, :destroy, :password_reset ]

  # GET /api/v1/users
  def index
    scope = User.order(:email)

    # Filters
    scope = scope.where("email ILIKE ?", "%#{params[:email]}%") if params[:email].present?
    scope = scope.where("display_name ILIKE ? OR first_name ILIKE ? OR last_name ILIKE ?",
      *Array.new(3, "%#{params[:name]}%")) if params[:name].present?
    scope = scope.where(status: params[:status]) if params[:status].present?

    result = paginate(scope)
    render json: {
      data: result[:data].map { |u| serialize_user(u) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/users/:id
  def show
    render json: { data: serialize_user(@user, detailed: true) }
  end

  # POST /api/v1/users
  def create
    # Shared with the admin UI (Admin::UsersController#create). The service
    # applies :admin/:status only for admin actors — this action is already
    # gated by before_action :authorize_admin! (defense in depth).
    user = UserProvisioningService.new(actor: current_user).build(params.require(:user))
    user.save!

    audit_log("api_user_created", subject: user, metadata: { email: user.email })
    render json: { data: serialize_user(user) }, status: :created
  end

  # PATCH /api/v1/users/:id
  # POST /api/v1/users/:id/password_reset
  #
  # #841 — a forgotten local-login password used to be unrecoverable: no admin
  # reset, no self-service flow, and the change screen requires the CURRENT
  # password. Two delivery routes, because deployments differ:
  #
  #   mode=temporary (default) — returns a temporary password for the admin to
  #     hand over out of band. The user MUST change it at first sign-in, so the
  #     credential the admin necessarily saw does not survive.
  #   mode=email — the app sends a one-time link. Requires SMTP; the token is
  #     never returned, because the point is that only the mailbox owner sees it.
  #
  # Either way the admin does not end up knowing a password the user keeps.
  def password_reset
    user = User.find(params[:id])

    unless user.active?
      return render json: { error: "Only an active user can be issued a password reset" },
                    status: :unprocessable_content
    end

    case params[:mode].presence || "temporary"
    when "temporary"
      temporary = user.issue_temporary_password!
      audit_log("admin_temporary_password_issued", subject: user,
                metadata: { target_user_id: user.id, target_email: user.email })

      render json: { data: {
        user_id: user.id, email: user.email, mode: "temporary",
        temporary_password: temporary,
        must_change_at_next_login: true,
        note: "Shown once. Convey it out of band; the user is required to change it when they sign in."
      } }, status: :created

    when "email"
      unless SparcConfig.enable_smtp?
        return render json: { error: "No mail is configured on this instance (SPARC_SMTP_ADDRESS); use mode=temporary" },
                      status: :unprocessable_content
      end

      token = user.issue_password_reset!
      PasswordResetMailer.reset_link(user, token, issued_by: current_user&.email).deliver_later
      audit_log("admin_password_reset_emailed", subject: user,
                metadata: { target_user_id: user.id, target_email: user.email,
                            expires_at: user.password_reset_expires_at&.iso8601 })

      # Deliberately no token in the response: emailing it and also returning it
      # would defeat the point of sending it to the mailbox owner.
      render json: { data: {
        user_id: user.id, email: user.email, mode: "email",
        expires_at: user.password_reset_expires_at&.utc&.iso8601,
        note: "A one-time link was emailed to the user. It is not retrievable here."
      } }, status: :created

    else
      render json: { error: "Unknown mode #{params[:mode].inspect}. Use \"temporary\" or \"email\"." },
             status: :unprocessable_content
    end
  end

  def update
    @user.update!(user_self_update_params)
    UserProvisioningService.new(actor: current_user).apply_privileged_attributes!(@user, params[:user])
    @user.save! if @user.changed?

    audit_log("api_user_updated", subject: @user, metadata: { email: @user.email })
    render json: { data: serialize_user(@user) }
  end

  # DELETE /api/v1/users/:id
  def destroy
    @user.deactivate!(reason: "Deactivated via API by #{current_user.email}")

    audit_log("api_user_deactivated", subject: @user, metadata: { email: @user.email })
    render json: { data: { id: @user.id, status: @user.status } }
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def authorize_admin_or_self!
    return if current_user.admin?
    return if current_user.id == @user.id

    raise NotAuthorizedError, "Not authorized to access this user"
  end

  # Self-service update: privilege-bearing :admin/:status are NOT permitted
  # here — they flow through UserProvisioningService#apply_privileged_attributes!
  # for admin actors only, never Rails mass-assignment. (Brakeman BRAKE0105.)
  def user_self_update_params
    params.require(:user).permit(:first_name, :last_name, :display_name, :email)
  end

  def serialize_user(user, detailed: false)
    data = {
      id: user.id,
      uuid: user.uuid,
      email: user.email,
      display_name: user.display_name,
      first_name: user.first_name,
      last_name: user.last_name,
      status: user.status,
      admin: user.admin?,
      created_at: user.created_at.iso8601,
      updated_at: user.updated_at.iso8601
    }

    if detailed
      data[:last_sign_in_at] = user.last_sign_in_at&.iso8601
      data[:sign_in_count] = user.sign_in_count
      data[:roles] = user.user_roles.includes(:role, :authorization_boundary).map do |ur|
        {
          role: ur.role.name,
          display_name: ur.role.display_name,
          scope: ur.role.scope,
          authorization_boundary: ur.authorization_boundary&.name
        }
      end
    end

    data
  end
end
