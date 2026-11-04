# frozen_string_literal: true

# #1340 — a field Rails re-renders with an error is outlined and carries its
# message (FieldErrorMarkup), in place of Rails' default `field_with_errors`
# wrapper, which nothing in SPARC styled, so no field was ever marked.
#
# The constant is resolved when a form renders, not at boot, so the autoloaded
# module reloads in development like any other.
ActiveSupport.on_load(:action_view) do
  ActionView::Base.field_error_proc = proc do |html_tag, instance|
    attribute = instance.instance_variable_get(:@method_name)
    messages = instance.object.errors.full_messages_for(attribute) if instance.object.respond_to?(:errors) && attribute
    FieldErrorMarkup.mark(html_tag, messages.presence || instance.error_message)
  end
end
