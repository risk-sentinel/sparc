# frozen_string_literal: true

# Privilege-safe user creation shared by the admin UI (Admin::UsersController)
# and the REST API (Api::V1::UsersController), so the UI stays a thin client
# over the same account-provisioning contract (API-first).
#
# It centralizes the mass-assignment guardrail: the privilege-bearing
# attributes +admin+ and +status+ are only ever set when the acting user is an
# admin, and never through Rails mass-assignment (Brakeman BRAKE0105 hardening).
#
# NIST AC-2 (Account Management) — administrative account provisioning.
class UserProvisioningService
  # Attributes any actor may set on a new user. Deliberately excludes :admin
  # and :status — those flow through +apply_privileged_attributes!+.
  #
  # #877 — and no longer :password / :password_confirmation. SPARC issues the
  # first credential itself (User#assign_temporary_password) and forces its
  # replacement at first sign-in, so a caller-supplied password is not merely
  # unnecessary, it is the thing being prevented: a credential the provisioning
  # admin chose, knew, and which survived indefinitely because nothing made the
  # user change it.
  #
  # Not permitted rather than accepted-and-overwritten, so a caller still
  # sending one gets no false impression that it took effect.
  #
  # Self-service registration is unaffected — RegistrationsController builds
  # User directly and still takes a password from the person it belongs to.
  BASE_ATTRIBUTES = %i[email first_name last_name display_name].freeze

  # @param actor [User, nil] the authenticated user performing the action
  def initialize(actor:)
    @actor = actor
  end

  # Build an unsaved User from a params-like object, applying privilege-bearing
  # attributes only when the actor is an admin. The caller decides how to
  # persist (save vs save!) and how to report errors.
  #
  # @param user_params [ActionController::Parameters, Hash]
  # @return [User]
  def build(user_params)
    user = User.new(permit_base(user_params))
    apply_privileged_attributes!(user, user_params)
    user
  end

  # Set +admin+/+status+ on an (existing or new) user, but only when the actor
  # is an admin. Safe to call on the self-service update path — it no-ops for
  # non-admin actors. Casts +admin+ like a form checkbox and validates +status+
  # against the enum before assigning.
  #
  # @param user [User]
  # @param user_params [ActionController::Parameters, Hash, nil]
  def apply_privileged_attributes!(user, user_params)
    return unless @actor&.admin?
    return if user_params.blank?

    admin_param  = fetch(user_params, :admin)
    status_param = fetch(user_params, :status)

    user.admin = ActiveModel::Type::Boolean.new.cast(admin_param) unless admin_param.nil?
    user.status = status_param if status_param.present? && User::STATUSES.include?(status_param.to_s)
    user
  end

  private

  def permit_base(user_params)
    if user_params.respond_to?(:permit)
      user_params.permit(*BASE_ATTRIBUTES)
    else
      user_params.to_h.symbolize_keys.slice(*BASE_ATTRIBUTES)
    end
  end

  def fetch(user_params, key)
    return nil unless user_params.respond_to?(:[])

    user_params[key].nil? ? user_params[key.to_s] : user_params[key]
  end
end
