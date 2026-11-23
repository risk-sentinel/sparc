# frozen_string_literal: true

# Renders a received version for review (#1390 part G): its sections, fields,
# list entries and small tables, with each change and validation error marked
# where it occurs and an "Ask about this" control on every place a reviewer
# may question.
#
# Every value a provider sent goes through `tag` / `safe_join` and is escaped:
# no HTML from a document is ever rendered, an address is shown as text and
# never linked or fetched (logos included). Rendering stops at MAX_NODES and
# says so, so a very large document cannot exhaust the page.
#
# NIST SP 800-53: SI-10 (untrusted input shown inert), CA-7, AU-10 (the
# question carries the exact place and values it is about).
module ReceivedDocumentViewerHelper
  MAX_NODES = 4_000
  MAX_DEPTH = 12
  DATE = /\A(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?\z/
  STATUS_VARIANTS = {
    /\A(implemented|passed|pass|final|remediated|fully mitigated|fixed)\z/i => "success",
    /partially|planned|interim|initial|skipped|notapplicable|not applicable|notchecked|informational/i => "warning",
    /\A(not implemented|failed|fail|error|open)\z/i => "danger"
  }.freeze

  # One rendering pass: what is being shown and how.
  #   mode     :current (changes marked with what was there before) or
  #            :compared (the compared version; changed places flagged)
  #   ask      offer "Ask about this" (only to a reviewer who may decide)
  #   open_all open every section and entry (Changed only switched off)
  ViewerContext = Struct.new(:viewer, :mode, :ask, :open_all, :errors_by_location, :budget, :cut, keyword_init: true) do
    def current? = mode == :current
    def spend! = (self.budget -= 1) >= 0
  end

  def viewer_context(viewer, mode:, ask:, open_all:, guidance: [])
    ViewerContext.new(viewer: viewer, mode: mode, ask: ask, open_all: open_all,
                      errors_by_location: guidance.index_by(&:location), budget: MAX_NODES)
  end

  # The document as sections, for the This version / compared version tabs.
  def viewer_document(ctx, data)
    sections = ctx.viewer.sections(data)
    return tag.p("Nothing to show.", class: "text-body-secondary p-3 mb-0") if sections.empty?

    safe_join(sections.map { |title, keys, base| viewer_section(ctx, title, keys, base, data) })
  end

  def viewer_section(ctx, title, keys, base, data)
    root = base.present? ? ExchangeDelta::JsonDiff.resolve(data, base) : data
    pointers = keys.map { |k| ctx.viewer.child_pointer(base, k) }
    changed = pointers.flat_map { |p| ctx.viewer.changes_under(p) }
    errors = ctx.errors_by_location.keys.count { |loc| pointers.any? { |p| loc == p || loc.start_with?("#{p}/") } }
    open = ctx.open_all || !ctx.viewer.compared? || changed.any? || errors.positive?
    tag.details(class: "sparc-viewer-section", open: open, data: { section: title }) do
      safe_join([
        tag.summary(class: "sparc-viewer-section__summary") do
          safe_join([ tag.h3(title, class: "h6 mb-0"), viewer_section_badges(ctx, changed, errors),
                      viewer_ask(ctx, pointers.first, title, "The #{title} section") ].compact)
        end,
        tag.div(class: "sparc-viewer-section__body") do
          if keys.size == 1 && root.is_a?(Hash) && viewer_list_of_records?(root[keys.first])
            viewer_list(ctx, root[keys.first], pointers.first, keys.first)
          else
            viewer_fields(ctx, root.is_a?(Hash) ? root : {}, base, keys)
          end
        end
      ])
    end
  end

  def viewer_section_badges(ctx, changed, errors)
    parts = []
    if changed.any?
      parts << (ctx.current? ? viewer_kind_counts(changed) : tag.span("#{changed.size} changed in the newer version", class: "sparc-status sparc-status--neutral"))
    elsif ctx.viewer.compared?
      parts << tag.span("No changes", class: "small text-body-secondary")
    end
    parts << tag.span(pluralize(errors, "error"), class: "sparc-status sparc-status--danger") if errors.positive?
    safe_join(parts, " ")
  end

  def viewer_kind_counts(changes)
    counts = changes.group_by(&:kind).transform_values(&:size)
    safe_join(ReceivedDocumentViewer::KIND_ORDER.keys.filter_map do |kind|
      next unless counts[kind]

      tag.span("#{counts[kind]} #{kind}#{'s' if counts[kind] > 1}", class: "sparc-status sparc-status--#{ExchangeHelper::CHANGE_KIND_VARIANTS[kind]}")
    end, " ")
  end

  # Fields of an object as label / value rows. `keys` limits and orders them.
  def viewer_fields(ctx, object, base, keys = nil, depth = 0)
    keys ||= object.keys
    keys = keys.reject { |k| k == "$schema" }
    rows = keys.select { |k| object.key?(k) }.map { |k| viewer_row(ctx, k, object[k], ctx.viewer.child_pointer(base, k), depth) }
    rows += viewer_dropped_fields(ctx, object, base, keys) if ctx.current?
    tag.dl(safe_join(rows), class: "sparc-viewer-fields")
  end

  def viewer_row(ctx, key, value, pointer, depth)
    return viewer_truncated(ctx) unless ctx.spend!

    label = ReceivedDocumentViewer::Layouts.label(key)
    if value.is_a?(Hash) || viewer_list_of_records?(value)
      body = if depth >= MAX_DEPTH then tag.span("(nested too deeply to show; see the download)", class: "text-body-secondary")
      elsif value.is_a?(Hash) then viewer_fields(ctx, value, pointer, nil, depth + 1)
      else viewer_list(ctx, value, pointer, key, depth + 1)
      end
      under = ctx.viewer.changes_under(pointer)
      return tag.div(class: "sparc-viewer-row sparc-viewer-row--block", id: viewer_anchor(pointer)) do
        safe_join([ tag.dt(safe_join([ label, (viewer_kind_counts(under) if under.any? && ctx.current?) ].compact, " ")), tag.dd(body) ])
      end
    end

    change = ctx.viewer.change_at(pointer)
    error = ctx.errors_by_location[pointer]
    value_html = value.is_a?(Array) ? viewer_scalar_list(ctx, value, pointer) : viewer_value(key, value)
    tag.div(class: viewer_row_class(change, error), id: viewer_anchor(pointer), data: { pointer: pointer }) do
      safe_join([
        tag.dt(label),
        tag.dd do
          safe_join([ tag.div(safe_join([ value_html, viewer_change_note(ctx, change), viewer_error_note(error) ].compact), class: "sparc-viewer-value"),
                      viewer_ask(ctx, pointer, ReceivedDocumentViewer.pointer_label(pointer), viewer_detail(change, error, label, value)) ].compact)
        end
      ])
    end
  end

  def viewer_row_class(change, error)
    classes = [ "sparc-viewer-row" ]
    classes << "sparc-viewer-mark sparc-viewer-mark--#{change.kind}" if change
    classes << "sparc-viewer-mark sparc-viewer-mark--error" if error
    classes.uniq.join(" ")
  end

  def viewer_change_note(ctx, change)
    return nil unless change

    badge = tag.span(ctx.current? ? change.kind.humanize : "Changed in the newer version",
                     class: "sparc-status sparc-status--#{ExchangeHelper::CHANGE_KIND_VARIANTS.fetch(change.kind, 'neutral')}")
    was = if ctx.current? && !change.before.nil? && !change.before.is_a?(Hash) && !change.before.is_a?(Array)
      tag.span(safe_join([ "Was ", tag.del(viewer_value(change.pointer.to_s.split("/").last, change.before)) ]), class: "sparc-viewer-was")
    elsif ctx.current? && change.before.nil?
      tag.span("New in this version", class: "sparc-viewer-was")
    end
    tag.div(safe_join([ badge, was ].compact, " "), class: "sparc-viewer-note")
  end

  def viewer_error_note(error)
    return nil unless error

    tag.div(class: "sparc-viewer-note") do
      safe_join([ tag.span("Error", class: "sparc-status sparc-status--danger"), " ", tag.strong(error.wrong),
                  (tag.span(safe_join([ "Needed: ", error.needed ]), class: "sparc-viewer-was") if error.needed.present?) ].compact)
    end
  end

  def viewer_detail(change, error, label, value)
    return "#{error.wrong} Needed: #{error.needed}".strip if error
    return change.summary if change

    text = value.is_a?(Array) ? value.map(&:to_s).join(", ") : value.to_s
    "#{label}: #{text.squish.truncate(200)}"
  end

  # Fields the compared version had and this one does not.
  def viewer_dropped_fields(ctx, object, base, keys)
    before = ctx.viewer.compared_value(base.presence || "")
    return [] unless before.is_a?(Hash)

    (keys.presence || before.keys).select { |k| before.key?(k) && !object.key?(k) && k != "$schema" }.map do |k|
      pointer = ctx.viewer.child_pointer(base, k)
      change = ctx.viewer.change_at(pointer)
      tag.div(class: viewer_row_class(change, nil), id: viewer_anchor(pointer)) do
        safe_join([ tag.dt(ReceivedDocumentViewer::Layouts.label(k)),
                    tag.dd(tag.div(safe_join([ tag.del(viewer_value(k, before[k])), " ",
                                               tag.span("Removed in this version", class: "sparc-status sparc-status--neutral") ]), class: "sparc-viewer-value")) ])
      end
    end
  end

  def viewer_scalar_list(ctx, list, pointer)
    return tag.span("None", class: "text-body-secondary") if list.empty?

    tag.ul(class: "sparc-viewer-values") do
      safe_join(list.each_with_index.map do |item, i|
        change = ctx.viewer.change_at("#{pointer}/#{i}")
        tag.li(safe_join([ viewer_value(nil, item), (viewer_change_note(ctx, change) if change) ].compact, " "))
      end)
    end
  end

  def viewer_list_of_records?(value) = value.is_a?(Array) && value.any? && value.all?(Hash)

  # A list of records: flat records as a table, others as entries.
  def viewer_list(ctx, list, pointer, name, depth = 0)
    return tag.span("None", class: "text-body-secondary") if list.blank?

    layout = ReceivedDocumentViewer::Layouts::ENTRIES[name.to_s]
    flat = !layout && list.all? { |r| r.is_a?(Hash) && r.values.none? { |v| v.is_a?(Hash) || v.is_a?(Array) } }
    return viewer_table(ctx, list, pointer) if flat

    entries = ctx.viewer.entries(list).map { |seg, entry| viewer_entry(ctx, entry, ctx.viewer.child_pointer(pointer, seg), name, depth) }
    entries += viewer_removed_entries(ctx, list, pointer, name) if ctx.current?
    tag.div(safe_join(entries), class: "sparc-viewer-entries")
  end

  def viewer_entry(ctx, entry, pointer, name, depth = 0, removed: false)
    return viewer_truncated(ctx) unless ctx.spend!

    layout = ReceivedDocumentViewer::Layouts::ENTRIES[name.to_s] || {}
    change = ctx.viewer.change_at(pointer)
    under = ctx.viewer.changes_under(pointer)
    kind = change&.kind || ctx.viewer.kind_under(pointer)
    title = viewer_dig(entry, layout[:title]).presence || pointer.split("/").last
    summary = viewer_dig(entry, layout[:summary])
    badges = [ (viewer_rating(viewer_dig(entry, layout[:rating])) if layout[:rating]),
               (viewer_status(viewer_dig(entry, layout[:status])) if layout[:status]) ].compact
    state = if removed then tag.span(ctx.current? ? "Removed in this version" : "Removed in the newer version", class: "sparc-status sparc-status--neutral")
    elsif change && change.before.nil? then tag.span(ctx.current? ? "New" : "Added in the newer version", class: "sparc-status sparc-status--#{ExchangeHelper::CHANGE_KIND_VARIANTS.fetch(change.kind, 'neutral')}")
    elsif under.any? then ctx.current? ? viewer_kind_counts(under) : tag.span("Changed in the newer version", class: "sparc-status sparc-status--neutral")
    end
    open = !removed && (ctx.open_all || kind.present?)
    tag.details(class: [ "sparc-viewer-entry", ("sparc-viewer-entry--#{kind}" if kind), ("sparc-viewer-entry--removed" if removed) ].compact.join(" "),
                open: open, id: viewer_anchor(pointer), data: { pointer: pointer }) do
      safe_join([
        tag.summary(class: "sparc-viewer-entry__summary") do
          safe_join([ tag.span(title.to_s.truncate(120), class: "fw-semibold"), *badges, state,
                      (tag.span(summary.to_s.squish.truncate(160), class: "sparc-viewer-entry__text") if summary.present?),
                      viewer_ask(ctx, pointer, ReceivedDocumentViewer.pointer_label(pointer), change&.summary || "#{title}: #{summary.to_s.squish.truncate(160)}") ].compact, " ")
        end,
        tag.div(class: "sparc-viewer-entry__body") do
          if removed && ctx.current?
            tag.p("Only in the compared version. Open its tab to read it.", class: "small text-body-secondary mb-0")
          else
            viewer_fields(ctx, entry, pointer, nil, depth + 1)
          end
        end
      ])
    end
  end

  # Entries the compared version had and this one does not.
  def viewer_removed_entries(ctx, list, pointer, name)
    before = ctx.viewer.compared_value(pointer)
    return [] unless before.is_a?(Array) && before.any?

    present = ctx.viewer.entries(list).map(&:first)
    ctx.viewer.entries(before).reject { |seg, _| present.include?(seg) }.map do |seg, entry|
      viewer_entry(ctx, entry, ctx.viewer.child_pointer(pointer, seg), name, removed: true)
    end
  end

  def viewer_table(ctx, list, pointer)
    columns = list.flat_map(&:keys).uniq
    rows = ctx.viewer.entries(list).map do |seg, record|
      row_pointer = ctx.viewer.child_pointer(pointer, seg)
      kind = ctx.viewer.kind_under(row_pointer)
      tag.tr(class: ("sparc-viewer-mark sparc-viewer-mark--#{kind}" if kind), id: viewer_anchor(row_pointer), data: { pointer: row_pointer }) do
        cells = columns.map do |col|
          change = ctx.viewer.change_at(ctx.viewer.child_pointer(row_pointer, col))
          tag.td(safe_join([ viewer_value(col, record[col]), (viewer_change_note(ctx, change) if change) ].compact, " "))
        end
        safe_join(cells + [ tag.td(viewer_ask(ctx, row_pointer, ReceivedDocumentViewer.pointer_label(row_pointer),
                                              ctx.viewer.changes_under(row_pointer).first&.summary || ReceivedDocumentViewer.pointer_label(row_pointer))) ])
      end
    end
    tag.div(class: "table-responsive") do
      tag.table(class: "table table-sm mb-0 sparc-viewer-table") do
        safe_join([ tag.thead(tag.tr(safe_join(columns.map { |c| tag.th(ReceivedDocumentViewer::Layouts.label(c)) } + [ tag.th(tag.span("Ask", class: "visually-hidden")) ]))),
                    tag.tbody(safe_join(rows)) ])
      end
    end
  end

  # A change's before/after value in the change list: as the document view
  # shows it (dates readable, addresses inert), long text cut short with the
  # full value on hover.
  def viewer_change_value(pointer, value)
    return "—" if value.nil? || value == ""

    key = pointer.to_s.split("/").last
    text = value.is_a?(String) ? value : delta_value(value)
    return tag.span(text.truncate(140), title: text) if text.length > 140

    value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false ? viewer_value(key, value) : text
  end

  # A value as text. Never a link, never HTML.
  def viewer_value(key, value)
    case value
    when nil then tag.span("(not given)", class: "sparc-viewer-blank")
    when true then "Yes"
    when false then "No"
    when Integer, Float
      ReceivedDocumentViewer::Layouts::RATING_FIELDS.include?(key.to_s) ? "N#{value}" : value.to_s
    when String
      return tag.span("(blank)", class: "sparc-viewer-blank") if value.strip.empty?
      return tag.span(value, class: "sparc-viewer-address", title: "Shown as text; SPARC does not open it") if value.match?(%r{\A[a-z][a-z0-9+.-]*://}i)

      viewer_date(value) || tag.span(value, class: "sparc-viewer-text")
    else value.to_json
    end
  end

  def viewer_date(value)
    m = value.match(DATE)
    return nil unless m

    month = Date::ABBR_MONTHNAMES[m[2].to_i]
    return nil unless month

    text = "#{m[3].to_i} #{month} #{m[1]}"
    text += " #{m[4]}:#{m[5]}#{m[6] == 'Z' ? ' UTC' : " #{m[6]}"}" if m[4]
    tag.time(text, datetime: value)
  end

  def viewer_rating(value)
    return nil unless value.is_a?(Integer)

    variant = value >= 3 ? "danger" : (value == 2 ? "warning" : "neutral")
    tag.span("N#{value}", class: "sparc-status sparc-status--#{variant}")
  end

  def viewer_status(value)
    return nil if value.blank?

    variant = STATUS_VARIANTS.find { |re, _| value.to_s.match?(re) }&.last || "neutral"
    tag.span(value.to_s.truncate(40), class: "sparc-status sparc-status--#{variant}")
  end

  # "Ask about this": adds the place, with what is there, to the reviewer's
  # questions (review_questions_controller.js). Offered only to a reviewer
  # who may decide this version.
  def viewer_ask(ctx, pointer, label, detail)
    return nil unless ctx.ask

    change = ctx.viewer.change_at(pointer)
    tag.button("Ask about this", type: "button", class: "sparc-viewer-ask",
                                 aria: { pressed: "false", label: "Ask the provider about #{label}" },
                                 data: { action: "review-questions#toggle", review_questions_target: "ask",
                                         pointer: pointer, label: label, detail: detail.to_s.truncate(900),
                                         before: change && !change.before.is_a?(Hash) ? delta_value(change.before).to_s.truncate(400) : nil,
                                         after: change && !change.after.is_a?(Hash) ? delta_value(change.after).to_s.truncate(400) : nil }.compact)
  end

  # A stable in-page anchor for a pointer (Show in document links to it).
  def viewer_anchor(pointer) = "vw-#{Digest::SHA256.hexdigest(pointer.to_s).first(16)}"

  def viewer_dig(entry, path)
    return nil if path.blank?

    path.split("/").reduce(entry) do |node, seg|
      case node
      when Hash then node[seg]
      when Array then seg.match?(/\A\d+\z/) ? node[seg.to_i] : nil
      end
    end
  end

  # Said once, where the limit is reached.
  def viewer_truncated(ctx)
    return nil if ctx.cut

    ctx.cut = true
    tag.p("The rest of this document is not shown here: it is larger than the viewer shows at once. Use the change list and the download.",
          class: "small text-body-secondary mb-0")
  end
end
