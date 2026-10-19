# frozen_string_literal: true

# #1176 — how every token-issuing path reads a token's limits from a request.
#
# Four paths issue tokens: the service-account form, the admin user page,
# /api/v1/users/:id/api_tokens and /api/v1/service_accounts. They read the
# same three things the same way, so they share this instead of the two list
# parsers that used to differ.
#
#   endpoints  an array (the picker posts `allowed_endpoints[]`, the API takes
#              a JSON array) or the older comma/newline-separated string
#   cidrs      the same shapes
#   days       a whole number of days; 0 means "never expires", which only a
#              person's token may have (ApiToken validates it)
module ApiTokenLimits
  extend ActiveSupport::Concern

  private

  # nil when the request did not mention the field at all, so a caller can
  # tell "not given" (carry the old limits over) from "given as empty"
  # (every endpoint).
  def token_list_param(raw)
    return nil if raw.nil?
    return raw.map { |v| v.to_s.strip }.reject(&:blank?) if raw.respond_to?(:map)

    raw.to_s.split(/[\r\n,]+/).map(&:strip).reject(&:blank?)
  end

  # The endpoint picker's submission. The picker always sends `endpoint_picker`,
  # so nothing ticked is told apart from "this client has no picker": an empty
  # list means EVERY endpoint, and an unticked form must never mean that.
  # Raises ArgumentError for the form to show; the API is unaffected.
  def picked_endpoints(raw)
    list = token_list_param(raw)
    if params[:endpoint_picker].present? && list.blank?
      raise ArgumentError, "Choose the endpoints this token may reach, or All endpoints"
    end

    list
  end

  # nil when not given. A non-numeric value is refused rather than read as 0,
  # which would mean "never expires".
  def token_days_param(raw)
    return nil if raw.blank?
    raise ArgumentError, "expires_in_days must be a whole number of days" unless raw.to_s.strip.match?(/\A\d+\z/)

    raw.to_i
  end

  def expiry_from_days(days)
    days&.positive? ? days.days.from_now : nil
  end
end
