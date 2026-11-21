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

  PUSH_STATUS_VARIANTS = { "pending" => "info", "confirmed" => "success", "unconfirmed" => "warning" }.freeze

  FORMAT_LABELS = { "fedramp" => "FedRAMP", "oscal" => "OSCAL", "hdf" => "HDF", "xccdf" => "XCCDF",
                    ReceivedDocument::MATERIAL_FORMAT => "Class A material" }.freeze

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

  def push_status_badge(status)
    return tag.span("Never pushed", class: "text-body-secondary") if status.blank?

    tag.span(status.to_s.humanize, class: "sparc-status sparc-status--#{PUSH_STATUS_VARIANTS.fetch(status.to_s, 'neutral')}",
                                   data: { push_status: status })
  end

  # Pushed bytes the fresh pull from the registered address did not confirm.
  def unconfirmed_push_badge(document)
    return unless document.unconfirmed_push?

    tag.span("Unconfirmed push", class: "sparc-status sparc-status--warning ms-1", data: { testid: "unconfirmed-push" },
                                 title: "The registered address did not return these bytes when SPARC pulled it")
  end

  # A Class A connection's certification: current, expired, or not recorded.
  def class_a_badge(connection)
    return tag.span("Not Class A", class: "sparc-status sparc-status--neutral") unless connection.class_a?
    return tag.span("Not recorded", class: "sparc-status sparc-status--warning") unless connection.class_a_recorded?

    if connection.class_a_expired?
      tag.span("Expired", class: "sparc-status sparc-status--danger", data: { testid: "class-a-expired" })
    else
      tag.span("Current", class: "sparc-status sparc-status--success")
    end
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
    if document.certification_material?
      material = ExchangeConnection::CLASS_A_MATERIALS.fetch(document.document_type, document.document_type)
      return "Class A material · #{material} for #{document.exchange_connection&.name || 'a connection'}"
    end

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
