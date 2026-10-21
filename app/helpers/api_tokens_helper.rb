# frozen_string_literal: true

# #1176 — what every token screen shows about a token's lifetime, from one
# place: the admin user page and the service-account pages read these.
module ApiTokensHelper
  STANDARD_EXPIRY_DAYS = [ 30, 60, 90, 180, 365 ].freeze

  # Choices for a new token's lifetime. A service account's token must expire
  # within SPARC_API_TOKEN_MAX_DAYS, so it gets no "Never" and nothing past the
  # cap. A person's token keeps "Never" (owner, 2026-10-18).
  def token_expiry_options(service_account:)
    max = SparcConfig.api_token_max_days
    days = STANDARD_EXPIRY_DAYS.select { |d| !service_account || d <= max }
    days |= [ max ] if service_account
    options = days.sort.map { |d| [ token_days_label(d), d ] }
    service_account ? options : options + [ [ "Never", 0 ] ]
  end

  def token_days_label(days)
    days == 365 ? "1 year" : "#{days} days"
  end

  # [label, badge class] for a token's state.
  def token_status(token)
    if token.expired?
      [ "Expired", "bg-danger" ]
    elsif token.expiring_soon?
      [ "Expires soon", "bg-warning text-dark" ]
    elsif token.never_expires?
      [ "Never expires", "bg-secondary" ]
    else
      [ "Active", "bg-success" ]
    end
  end

  def token_status_badge(token)
    label, css = token_status(token)
    tag.span(label, class: "badge #{css}")
  end

  # The picker's starting state. nil is a fresh form, which starts on All
  # endpoints, the default before #1176. A re-shown form keeps what was
  # submitted, so a refused "nothing ticked" is not quietly turned into All.
  def endpoint_picker_all?(selected)
    selected.nil? || selected.include?(ApiEndpointCatalog::ALL)
  end
end
