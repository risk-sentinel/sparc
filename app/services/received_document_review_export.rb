# frozen_string_literal: true

# A received version's review, written out to share with the provider out of
# band (#1390 part G; owner, 2026-11-23): Markdown for a person to read and
# JSON for a system. #1394 will send it automatically; until then a reviewer
# downloads it and passes it on by whatever channel the agency uses.
#
# It carries the document's identity (type, provider ID, version, SHA-256),
# the recorded comparison it was reviewed against, the decision and note,
# every question with its location and values, and, for a version that
# failed validation, each error with what is needed.
#
# Everything comes from the record; nothing is fetched. The Markdown escapes
# provider-supplied text so it cannot inject links or HTML into a reader's
# renderer (SI-10).
#
# NIST SP 800-53: AU-10 (what was asked, by whom, of which exact bytes),
# CA-2, SI-10.
class ReceivedDocumentReviewExport
  # A question's fields in the order the export lists them, with their labels.
  QUESTION_FIELDS = { "pointer" => "Location", "detail" => nil, "before" => "Before", "after" => "After", "question" => "Question" }.freeze

  FORMAT_VERSION = "1"

  def initialize(document, viewer: nil)
    @document = document
    @viewer = viewer || ReceivedDocumentViewer.new(document)
  end

  def filename(ext)
    base = [ "review", @document.document_type.presence || @document.format, "v#{@viewer.version_number(@document)}", @document.sha256.first(12) ]
    "#{base.join('-').parameterize}.#{ext}"
  end

  def as_json(*)
    doc = @document
    baseline = @viewer.baseline
    {
      sparc_review_export: FORMAT_VERSION,
      exported_at: Time.current.utc.iso8601,
      boundary: { id: doc.authorization_boundary_id, name: doc.authorization_boundary.name },
      document: {
        id: doc.id, format: doc.format, document_type: doc.document_type, fedramp_id: doc.fedramp_id,
        version: @viewer.version_number(doc), filename: doc.filename, sha256: doc.sha256, byte_size: doc.byte_size,
        received_at: doc.received_at&.utc&.iso8601, source: doc.source, state: doc.state, valid: doc.valid_document
      },
      compared_with: baseline && {
        id: baseline.id, version: @viewer.version_number(baseline), sha256: baseline.sha256, state: baseline.state,
        counts: @viewer.recorded_counts
      },
      review: {
        action: doc.review_action, note: doc.review_note, reviewed_at: doc.reviewed_at&.utc&.iso8601,
        reviewed_by: doc.reviewed_by&.display_label
      },
      questions: doc.questions,
      validation_errors: guidance.map do |item|
        { check: item.check, pointer: item.pointer, location: item.label, wrong: item.wrong, needed: item.needed, message: item.message }
      end
    }
  end

  def to_markdown
    data = as_json
    lines = md_summary(data)
    lines.concat(md_decision(data[:review]))
    lines.concat(md_questions(data[:questions]))
    lines.concat(md_validation(data[:validation_errors]))
    lines << "" << "_Exported from SPARC on #{data[:exported_at]}._" << ""
    lines.join("\n")
  end

  private

  def md_summary(data)
    doc = data[:document]
    lines = [ "# Review of #{md(title)} version #{doc[:version]}", "",
              "- Boundary: #{md(data[:boundary][:name])}",
              "- Document: #{md(title)}#{doc[:fedramp_id] ? " (FedRAMP ID #{md(doc[:fedramp_id])})" : ''}, version #{doc[:version]}",
              "- File: #{md(doc[:filename] || '—')}, SHA-256 `#{doc[:sha256]}`",
              "- Received: #{doc[:received_at]} (#{doc[:source]})",
              "- State: #{doc[:state].to_s.humanize}#{doc[:valid] ? '' : ' (failed validation)'}" ]
    if (cw = data[:compared_with])
      c = cw[:counts]
      lines << "- Reviewed against: version #{cw[:version]} (#{cw[:state].to_s.humanize.downcase}), SHA-256 `#{cw[:sha256]}`: " \
               "#{c['regression']} regressions, #{c['improvement']} improvements, #{c['neutral']} neutral changes"
    end
    lines
  end

  def md_decision(review)
    lines = [ "", "## Decision", "" ]
    return lines << "Not decided yet." unless review[:action]

    lines << "#{review[:action] == 'auto_accept' ? 'Accepted without review' : review[:action].humanize} on #{review[:reviewed_at]}#{review[:reviewed_by] ? " by #{md(review[:reviewed_by])}" : ''}."
    lines << "" << quote(review[:note]) if review[:note].present?
    lines
  end

  def md_questions(questions)
    return [] if questions.empty?

    lines = [ "", "## Questions for the provider", "" ]
    questions.each_with_index do |q, i|
      lines << "#{i + 1}. **#{md(q['label'] || q['pointer'] || 'General')}**"
      QUESTION_FIELDS.each do |field, label|
        lines << "   - #{"#{label}: " if label}#{md(q[field])}" if q[field].present?
      end
    end
    lines
  end

  def md_validation(errors)
    return [] if errors.empty?

    lines = [ "", "## Why this version failed validation", "" ]
    errors.each_with_index do |e, i|
      lines << "#{i + 1}. **#{md(e[:location])}** (#{e[:check]} check)"
      lines << "   - What is wrong: #{md(e[:wrong])}"
      lines << "   - What is needed: #{md(e[:needed])}" if e[:needed].present?
      lines << "   - Validator: #{md(e[:pointer].presence || '/')} #{md(e[:message])}"
    end
    lines
  end

  def guidance = @guidance ||= ValidationGuidance.new(@document).items

  def title
    @document.document_type.present? ? @document.document_type.tr("-", " ").capitalize : @document.format.upcase
  end

  # Provider-supplied text as inert Markdown: no HTML, links, images or
  # emphasis, one line.
  def md(text)
    text.to_s.squish.gsub(/[\\`*_{}\[\]()#+!|<>~]/) { |c| "\\#{c}" }
  end

  def quote(text) = text.to_s.lines.map { |l| "> #{md(l)}" }.join("\n")
end
