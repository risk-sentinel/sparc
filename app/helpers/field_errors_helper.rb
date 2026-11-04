# frozen_string_literal: true

# #1340 — FieldErrorMarkup for fields a view builds by hand (no form builder),
# such as the SSP Enrich page's repeated rows. Use all three on one field:
#
#   <input id="x" class="form-control<%= field_invalid_class(row, :title) %>"
#          <%= field_invalid_attributes(row, :title, "x") %>>
#   <%= field_error_feedback(row, :title, "x") %>
module FieldErrorsHelper
  def field_errors_for(record, attribute)
    record.respond_to?(:errors) ? record.errors[attribute] : []
  end

  def field_invalid?(record, attribute) = field_errors_for(record, attribute).any?

  def field_invalid_class(record, attribute)
    field_invalid?(record, attribute) ? " #{FieldErrorMarkup::INVALID_CLASS}" : ""
  end

  def field_invalid_attributes(record, attribute, field_id)
    return "" unless field_invalid?(record, attribute)

    tag.attributes("aria-invalid": "true", "aria-describedby": FieldErrorMarkup.feedback_id(field_id))
  end

  def field_error_feedback(record, attribute, field_id)
    return unless field_invalid?(record, attribute)

    FieldErrorMarkup.feedback(field_id, record.errors.full_messages_for(attribute))
  end
end
