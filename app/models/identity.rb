# frozen_string_literal: true

# Links a User to an external OAuth/OIDC/LDAP provider.
# A user can have multiple identities (e.g., GitHub + Okta).
#
# The mfa_data column is reserved for Phase 5 MFA evidence collection.
class Identity < ApplicationRecord
  belongs_to :user

  validates :provider, presence: true
  validates :uid, presence: true, uniqueness: { scope: :provider }

  PROVIDERS = %w[github gitlab oidc ldap].freeze
  validates :provider, inclusion: { in: PROVIDERS }

  scope :for_provider, ->(provider) { where(provider: provider) }

  # Find or initialize an identity from an OmniAuth auth hash.
  #
  #   Identity.from_omniauth(request.env["omniauth.auth"])
  def self.from_omniauth(auth)
    find_or_initialize_by(provider: auth.provider, uid: auth.uid.to_s) do |identity|
      identity.email = auth.info&.email
      identity.auth_data = auth.to_h.except("credentials")
    end
  end

  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end
end
