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
#
class Api::V1::UsersController < Api::V1::BaseController
  before_action :set_user, only: [ :show, :update, :destroy ]
  before_action :authorize_admin_or_self!, only: [ :show, :update ]
  before_action :authorize_admin!, only: [ :index, :create, :destroy ]

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
    user = User.new(user_create_params)
    user.save!

    audit_log("api_user_created", subject: user, metadata: { email: user.email })
    render json: { data: serialize_user(user) }, status: :created
  end

  # PATCH /api/v1/users/:id
  def update
    permitted = current_user.admin? ? user_admin_update_params : user_self_update_params
    @user.update!(permitted)

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

  def user_create_params
    params.require(:user).permit(:email, :password, :password_confirmation,
      :first_name, :last_name, :display_name, :admin)
  end

  def user_admin_update_params
    params.require(:user).permit(:email, :first_name, :last_name, :display_name,
      :admin, :status)
  end

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
