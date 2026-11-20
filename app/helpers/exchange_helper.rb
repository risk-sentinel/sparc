# frozen_string_literal: true

# #1354 — labels and badges for connections and received documents, shared by
# the Connections screens and a boundary's Received documents page so a state
# reads the same everywhere. Variants are the existing sparc-status ones.
module ExchangeHelper
  RECEIVED_STATE_LABELS = {
    "pending_review" => "Pending review", "accepted" => "Accepted", "responded" => "Responded",
    "rejected" => "Rejected", "superseded" => "Superseded", "invalid" => "Invalid"
  }.freeze

  RECEIVED_STATE_VARIANTS = {
    "pending_review" => "warning", "accepted" => "success", "responded" => "info",
    "rejected" => "danger", "superseded" => "neutral", "invalid" => "danger"
  }.freeze

  PULL_STATUS_VARIANTS = { "stored" => "success", "unchanged" => "neutral", "failed" => "danger" }.freeze

  FORMAT_LABELS = { "fedramp" => "FedRAMP", "oscal" => "OSCAL", "hdf" => "HDF", "xccdf" => "XCCDF" }.freeze

  CHANGE_KIND_VARIANTS = { "regression" => "danger", "improvement" => "success", "neutral" => "neutral" }.freeze

  AUTH_SCHEME_LABELS = { "none" => "None", "bearer" => "Bearer token", "header" => "Named header" }.freeze

  def received_state_badge(state)
    tag.span(RECEIVED_STATE_LABELS.fetch(state.to_s, state.to_s.humanize),
             class: "sparc-status sparc-status--#{RECEIVED_STATE_VARIANTS.fetch(state.to_s, 'neutral')}",
             data: { received_state: state })
  end

  def pull_status_badge(status)
    return tag.span("Never pulled", class: "text-body-secondary") if status.blank?

    tag.span(status.to_s.humanize, class: "sparc-status sparc-status--#{PULL_STATUS_VARIANTS.fetch(status.to_s, 'neutral')}",
                                   data: { pull_status: status })
  end

  def exchange_format_label(format) = FORMAT_LABELS.fetch(format.to_s, format.to_s.upcase)

  def change_kind_badge(kind)
    tag.span(kind.to_s.humanize, class: "sparc-status sparc-status--#{CHANGE_KIND_VARIANTS.fetch(kind.to_s, 'neutral')}")
  end

  # Where a version came from: a pull from a named connection, or an upload.
  def received_source_label(document)
    if document.source == "upload"
      "Upload"
    else
      name = document.exchange_connection&.name || "a deleted connection"
      "#{document.source.humanize} · #{name}"
    end
  end

  # A stream: one pulled document address, or a boundary's uploads of one
  # format and document type.
  def received_stream_label(document)
    kind = [ exchange_format_label(document.format), document.document_type.presence ].compact.join(" · ")
    if document.exchange_document_source
      "#{kind} from #{document.exchange_connection&.name || 'a connection'} (#{document.exchange_document_source.url})"
    elsif document.source == "upload"
      "#{kind} uploads"
    else
      kind
    end
  end

  def exchange_time(time) = time ? time.utc.strftime("%Y-%m-%d %H:%M UTC") : "—"

  # A before/after value from a stored delta, as text.
  def delta_value(value)
    return "—" if value.nil? || value == ""

    value.is_a?(String) ? value : value.to_json
  end
end
