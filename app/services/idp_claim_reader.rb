# frozen_string_literal: true

# #860 — pull the grants claim out of an OmniAuth response.
#
# Small, and separate from the sync, because the distinction it draws is the one
# the whole epic turns on: **a claim that is ABSENT is not a claim that is
# EMPTY.** An absent claim says nothing about a user's entitlements — the claim
# name may be misconfigured, the scope may not have been granted, the IdP may
# have been upgraded — and syncing on it would read a configuration mistake as
# "this person should have nothing". An empty claim is a real statement.
#
# Getting that wrong is how the naive implementation de-provisions a customer,
# so it is decided HERE, once, on the raw provider payload, rather than inferred
# later from an empty array that has already lost the difference.
class IdpClaimReader
  Result = Struct.new(:values, :present, keyword_init: true) do
    def present? = present
  end

  def initialize(auth, claim_name: nil)
    @auth = auth
    @claim_name = claim_name || SparcConfig.oidc_grants_claim
  end

  def read
    raw = raw_claims
    return Result.new(values: [], present: false) if raw.nil? || !raw.key?(@claim_name)

    Result.new(values: Array(raw[@claim_name]).map(&:to_s), present: true)
  end

  private

  # omniauth-openid-connect exposes the id_token/userinfo claims on
  # `extra.raw_info`. `info` is OmniAuth's own normalised subset and does NOT
  # carry arbitrary claims, so reading groups from it would silently find
  # nothing on every provider.
  def raw_claims
    extra = @auth.respond_to?(:extra) ? @auth.extra : nil
    raw = extra.respond_to?(:raw_info) ? extra.raw_info : nil
    return nil if raw.nil?

    raw.respond_to?(:to_h) ? raw.to_h.transform_keys(&:to_s) : nil
  end
end
