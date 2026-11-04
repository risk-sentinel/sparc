# frozen_string_literal: true

# #1340 — how a form field with an error is marked, in one place.
#
# A field whose value was refused gets Bootstrap's invalid outline
# (`is-invalid`, its existing red, no new colour), `aria-invalid="true"`, and
# its message directly below it, which `aria-describedby` points at so a
# screen reader reads the message with the field.
#
# Two ways in, one result:
# - forms built on a record (`form_with model:`) get it from Rails'
#   `field_error_proc` (config/initializers/field_error_proc.rb), with no change
#   to the form;
# - hand-built fields (the SSP Enrich rows) call FieldErrorsHelper, which
#   reads the same id and class rules from here.
#
# NIST SP 800-53 Rev 5: SI-10 (information input validation: the refused
# input is identified to the person who entered it).
module FieldErrorMarkup
  INVALID_CLASS = "is-invalid"
  FEEDBACK_CLASS = "invalid-feedback d-block"
  SKIPPED_TYPES = %w[hidden submit button].freeze

  extend self

  def feedback_id(field_id) = "#{field_id}-error"

  # The message element shown under a field: its full messages ("Title can't
  # be blank"), so it reads on its own.
  def feedback(field_id, messages)
    text = ERB::Util.html_escape(Array(messages).to_sentence)
    %(<div class="#{FEEDBACK_CLASS}" id="#{ERB::Util.html_escape(feedback_id(field_id))}" data-field-error>#{text}</div>).html_safe
  end

  # field_error_proc: mark the tag Rails hands over, and put its message after
  # it. Labels and hidden inputs are left as they are.
  def mark(html_tag, messages)
    fragment = Nokogiri::HTML5::DocumentFragment.parse(html_tag.to_s)
    field = fragment.element_children.first
    return html_tag if field.nil? || field.name == "label" || SKIPPED_TYPES.include?(field["type"].to_s)

    field_id = field["id"].presence || "field-#{SecureRandom.hex(4)}"
    field["id"] = field_id
    field["class"] = [ field["class"], INVALID_CLASS ].compact.join(" ").strip
    field["aria-invalid"] = "true"
    field["aria-describedby"] = [ field["aria-describedby"], feedback_id(field_id) ].compact.join(" ").strip
    (fragment.to_html + feedback(field_id, messages)).html_safe
  end
end
