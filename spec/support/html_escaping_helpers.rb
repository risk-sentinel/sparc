# frozen_string_literal: true

# One convention for asserting generated text against rendered HTML.
#
# Rails escapes interpolated text, so a Faker-generated value containing
# ' & < > or " — e.g. "Schiller, O'Hara and Abbott ATO" from Faker::Company.name
# — renders as "Schiller, O&#39;Hara and Abbott ATO". A spec comparing the raw
# value against response.body then passes or fails depending on what Faker
# happened to roll, which looks like a flaky test but is an assertion bug. It is
# NOT seed-dependent: Faker has its own RNG, independent of RSpec's --seed, so
# re-running with the same seed proves nothing.
#
# Worse, `expect(body).not_to include(raw_value)` passes VACUOUSLY whenever the
# value contains an escapable character — the assertion silently stops testing
# anything.
#
# The suite previously mixed three conventions (CGI.escapeHTML,
# ERB::Util.html_escape, and raw comparison). Use `html_text` everywhere.
#
# For structural assertions — "this option is selected", "this row exists" —
# prefer parsing the response with Nokogiri and asserting on the decoded text,
# which sidesteps escaping entirely.
module HtmlEscapingHelpers
  # The value as it appears in rendered HTML.
  def html_text(value)
    ERB::Util.html_escape(value.to_s)
  end
end

RSpec.configure do |config|
  config.include HtmlEscapingHelpers, type: :request
  config.include HtmlEscapingHelpers, type: :system
  config.include HtmlEscapingHelpers, type: :helper
  config.include HtmlEscapingHelpers, type: :view
end
