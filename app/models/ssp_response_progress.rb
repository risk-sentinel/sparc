# frozen_string_literal: true

# #1242 — how much of an SSP is answered, counted in responses rather than
# controls. One definition, read by the SSP screen's header, each control's
# badge and statements table, the SSP list, and the API.
#
# The REQUIRED set comes from the SSP's own baseline, never from the rows the
# SSP happens to store: every statement part with no statement part below it,
# per control the profile selects, as the profile's alters leave the catalog
# (ControlRequirementText#required). A control the catalog holds no parts for
# needs one response, its `_smt`. An SSP with no profile falls back to its own
# controls against the catalog. A required part with no row is missing; it does
# not drop out of the count.
#
# Each required part is in one state. The names are NIST's (SP 800-53 Rev 5
# §2.5 and SP 800-37 Rev 2 describe inherited, hybrid and system-specific
# controls) and each is one OSCAL can carry: `inherited` and `satisfied` on a
# by-component, against the provider's `export.provided` / `responsibilities`.
#
#   inherited                   an active leveraged link to a provider statement
#                               that is `provided` only
#   hybrid_satisfied            the provider statement is `provided` and hands
#                               a responsibility back; this system wrote its part
#   hybrid_unsatisfied          the same, with this system's part not written
#   responsibility_unsatisfied  the provider hands the whole part back (a
#                               responsibility, nothing provided) and it is not
#                               written yet; written, it is `implemented`
#   implemented                 this system's own text: authored, edited, or
#                               filled from a CDEF (`cdef_unreviewed` counts the
#                               CDEF text nobody has marked reviewed)
#   missing                     nothing written
#
# Text written at a level that has parts below it (`ac-1_smt` when `ac-1_smt.a`
# exists) answers none of them; it is counted as `parent_level_text` so the
# screen can tell the author to split it.
#
# NIST 800-53: PL-2 (the plan states how each requirement is met), CA-2.
class SspResponseProgress
  STATES = %w[inherited hybrid_satisfied hybrid_unsatisfied responsibility_unsatisfied implemented missing].freeze
  OWED   = %w[hybrid_unsatisfied responsibility_unsatisfied missing].freeze

  LABELS = {
    "inherited" => "Inherited",
    "hybrid_satisfied" => "Hybrid, satisfied",
    "hybrid_unsatisfied" => "Hybrid, responsibility not yet satisfied",
    "responsibility_unsatisfied" => "Customer responsibility, not yet satisfied",
    "implemented" => "Implemented",
    "missing" => "Missing"
  }.freeze

  # #1312 — `implementation_status` and `control_origination` are the item's
  # own (SspControlStatement), nil and [] for a missing row.
  Part = Struct.new(:control_id, :part_id, :statement_id, :state, :cdef_unreviewed,
                    :implementation_status, :control_origination, keyword_init: true) do
    def not_in_place? = SspControlStatement::NOT_IN_PLACE.include?(implementation_status)
  end

  # #1312 — what a control's items record: status counts and whether it is a
  # hybrid. Read by the control's summary line, the SSP heatmap, the dashboard,
  # SAR and SAP generation and the HDF export, so they cannot disagree.
  class ItemSummary
    NOT_SET = "Not set"
    STATUS_ORDER = [ *SspControlStatement::IMPLEMENTATION_STATUSES, nil ].freeze

    attr_reader :parts

    def initialize(parts)
      @parts = parts
    end

    def size = parts.size

    # status (nil for not set) => count, in OSCAL's order, zeros left out.
    def status_counts
      counts = parts.group_by(&:implementation_status).transform_values(&:size)
      STATUS_ORDER.filter_map { |status| [ status, counts[status] ] if counts[status] }.to_h
    end

    def originations = parts.flat_map { Array(_1.control_origination) }.uniq

    # NIST's hybrid control: part of it inherited, part this system's own.
    # Either an item is partly inherited, or some items are inherited and
    # others are not. Items with no origination yet do not count either way.
    def hybrid?
      set = parts.map { Array(_1.control_origination) }.reject(&:empty?)
      return false if set.empty?

      set.any? { _1.include?(SspControlStatement::INHERITED) && _1.size > 1 } ||
        set.map { _1.include?(SspControlStatement::INHERITED) }.uniq.size > 1
    end

    def fully_inherited? = parts.any? && parts.all? { Array(_1.control_origination) == [ SspControlStatement::INHERITED ] }

    def not_in_place = parts.select(&:not_in_place?)

    def self.label(status) = SspControlStatement::STATUS_LABELS.fetch(status, NOT_SET)

    # Every status label, in OSCAL's order, "Not set" last: heatmap columns.
    LABEL_ORDER = STATUS_ORDER.map { label(_1) }.freeze

    # One label for the whole control, for its card: the status every item
    # shares; otherwise Partial while any item is not in place, Not set while
    # any is unanswered, else Implemented (a mix of implemented, alternative
    # and not applicable is in place).
    def headline_label
      statuses = parts.map(&:implementation_status).uniq
      return NOT_SET if statuses.empty?
      return self.class.label(statuses.first) if statuses.size == 1
      return self.class.label("partial") if parts.any?(&:not_in_place?)
      return NOT_SET if statuses.include?(nil)

      self.class.label("implemented")
    end

    # "12 of 18 implemented · 2 planned · hybrid"
    def to_s
      return "No items" if parts.empty?

      counts = status_counts
      words = [ "#{counts.fetch('implemented', 0)} of #{size} implemented" ]
      counts.each do |status, count|
        next if status == "implemented"

        words << "#{count} #{self.class.label(status).downcase}"
      end
      words << "hybrid" if hybrid?
      words << "inherited" if fully_inherited?
      words.join(" · ")
    end
  end

  # Counts for one control or the whole document.
  class Tally
    attr_reader :counts, :cdef_unreviewed, :parent_level_text

    def initialize(parts, parent_level_text: 0)
      @counts = STATES.index_with(0)
      parts.each { |part| @counts[part.state] += 1 }
      @cdef_unreviewed = parts.count(&:cdef_unreviewed)
      @parent_level_text = parent_level_text
    end

    def required = counts.values.sum
    def owed     = counts.values_at(*OWED).sum
    def done     = required - owed
    def complete? = owed.zero?

    def to_h
      counts.merge("required" => required, "done" => done, "owed" => owed,
                   "cdef_unreviewed" => cdef_unreviewed, "parent_level_text" => parent_level_text)
    end
  end

  # `required_cache` — a Hash a caller keeps across several documents (the SSP
  # list, an API page), so documents on one baseline compute it once.
  def self.for(document, required_cache: {})
    key = document.profile_document_id ? "profile-#{document.profile_document_id}" : "ssp-#{document.id}"
    new(document, required: required_cache[key] ||= required_for(document))
  end

  # document id => progress, for several documents at once.
  def self.for_documents(documents, required_cache: {})
    documents.to_h { |doc| [ doc.id, self.for(doc, required_cache: required_cache) ] }
  end

  # canonical control id => [required part ids], in catalog order.
  def self.required_for(document)
    profile = document.profile_document
    ids =
      if profile
        profile.profile_controls.order(:row_order, :id).pluck(:control_id)
      else
        document.ssp_controls.where(parent_id: nil).order(:row_order, :id).pluck(:control_id)
      end
    texts = ControlRequirementText.for_profile(profile).for_controls(ids)

    ids.each_with_object({}) do |id, required|
      key = ControlId.canonical(id)
      required[key] ||= texts[key]&.required.presence || [ "#{key}_smt" ]
    end
  end

  attr_reader :document, :required

  def initialize(document, required: nil)
    @document = document
    @required = required || self.class.required_for(document)
  end

  def total = @total ||= Tally.new(parts, parent_level_text: parent_level_text_rows.size)

  def for_control(control_id)
    key = ControlId.canonical(control_id)
    return nil unless required.key?(key)

    (@per_control ||= {})[key] ||=
      Tally.new(parts_by_control.fetch(key, []),
                parent_level_text: parent_level_text_rows.count { _1[:control] == key })
  end

  def parts_for(control_id) = parts_by_control.fetch(ControlId.canonical(control_id), [])

  # #1312 — what a control's items record (ItemSummary), or nil when the
  # baseline does not select the control.
  def items_for(control_id)
    key = ControlId.canonical(control_id)
    return nil unless required.key?(key)

    (@items_per_control ||= {})[key] ||= ItemSummary.new(parts_by_control.fetch(key, []))
  end

  # Every required item on the document.
  def items = @items ||= ItemSummary.new(parts)

  # statement row id => Part, for the rows that are required responses.
  def part_for_statement(statement_id) = parts_by_statement[statement_id]

  # Statement row ids whose text sits above the parts that need it.
  def parent_level_statement_ids = parent_level_text_rows.map { _1[:id] }.to_set

  def to_h = total.to_h

  private

  def parts
    @parts ||= required.flat_map do |control, part_ids|
      part_ids.map { |part_id| classify(control, part_id) }
    end
  end

  def parts_by_control = @parts_by_control ||= parts.group_by(&:control_id)

  def parts_by_statement = @parts_by_statement ||= parts.select(&:statement_id).index_by(&:statement_id)

  def classify(control, part_id)
    row = rows[[ control, part_id.downcase ]]
    unless row
      return Part.new(control_id: control, part_id: part_id, state: "missing", cdef_unreviewed: false,
                      control_origination: [])
    end

    state, unreviewed = state_of(row)
    Part.new(control_id: control, part_id: part_id, statement_id: row[:id], state: state, cdef_unreviewed: unreviewed,
             implementation_status: row[:status], control_origination: origination_of(row, state))
  end

  def state_of(row)
    links = links_by_statement.fetch(row[:id], [])
    leveraged = links.find { _1[:source_type] == "SspControlStatement" }
    decided = leveraged && leveraged_state(leveraged, row[:written])
    return [ decided, false ] if decided
    return [ "missing", false ] unless row[:written]

    cdef = links.find { _1[:source_type] == "CdefControlStatement" && !_1[:overridden] }
    [ "implemented", cdef.present? && cdef[:reviewed_at].nil? ]
  end

  # #1312 — what the item records, a leveraged link's answer first, as
  # SspControlStatement#effective_origination decides it.
  def origination_of(row, state)
    own = Array(row[:origination])
    case state
    when "inherited" then [ SspControlStatement::INHERITED ]
    when "hybrid_satisfied", "hybrid_unsatisfied"
      [ SspControlStatement::INHERITED, *((own - [ SspControlStatement::INHERITED ]).presence || [ SspControlStatement::SYSTEM_SPECIFIC ]) ]
    else own
    end
  end

  # [hybrid, written] => state, for a provider statement that hands a
  # responsibility back.
  RESPONSIBILITY_STATES = {
    [ true, true ] => "hybrid_satisfied", [ true, false ] => "hybrid_unsatisfied",
    [ false, true ] => "implemented", [ false, false ] => "responsibility_unsatisfied"
  }.freeze
  private_constant :RESPONSIBILITY_STATES

  # The state a leveraged link decides, or nil when this system's own text
  # decides it (an overridden plain inheritance).
  def leveraged_state(link, written)
    tags = source_tags.fetch(link[:source_id], [])
    if tags.include?(SspControlStatement::RESPONSIBILITY_TAG)
      return RESPONSIBILITY_STATES.fetch([ tags.include?(SspControlStatement::PROVIDED_TAG), written ])
    end

    link[:overridden] ? nil : "inherited"
  end

  # [canonical control id, downcased statement_id] => row, root controls only.
  def rows
    @rows ||= SspControlStatement.joins(:ssp_control)
                                 .where(ssp_controls: { ssp_document_id: document.id, parent_id: nil })
                                 .pluck(:id, "ssp_controls.control_id", :statement_id,
                                        # Any non-space character, as Ruby's `present?` reads it:
                                        # BTRIM strips spaces only, so a newline counted as written.
                                        Arel.sql("COALESCE(ssp_control_statements.implementation_prose ~ '[^[:space:]]', false)"),
                                        :implementation_status, :control_origination)
                                 .to_h do |id, control_id, statement_id, written, status, origination|
                                   key = [ ControlId.canonical(control_id), statement_id.to_s.downcase ]
                                   [ key, { id: id, written: written, status: status, origination: origination } ]
                                 end
  end

  def links_by_statement
    @links_by_statement ||= SspControlStatementInheritance
                              .where(ssp_control_statement_id: rows.values.map { _1[:id] })
                              .pluck(:ssp_control_statement_id, :source_type, :source_id, :overridden, :reviewed_at)
                              .group_by(&:first)
                              .transform_values do |list|
                                list.map { |_, type, source, overridden, reviewed| { source_type: type, source_id: source, overridden: overridden, reviewed_at: reviewed } }
                              end
  end

  # provider statement id => its provided / responsibility tags
  def source_tags
    @source_tags ||= begin
      ids = links_by_statement.values.flatten.select { _1[:source_type] == "SspControlStatement" }.map { _1[:source_id] }
      SspControlStatement.where(id: ids).pluck(:id, :set_parameters_data).to_h do |id, data|
        [ id, Array(data).filter_map { _1.is_a?(Hash) ? _1["tag"] : nil } ]
      end
    end
  end

  # Rows in a required control that are not themselves required but carry text.
  def parent_level_text_rows
    @parent_level_text_rows ||= begin
      required_keys = required.flat_map { |control, ids| ids.map { [ control, _1.downcase ] } }.to_set
      rows.filter_map do |(control, statement), row|
        next unless required.key?(control) && row[:written] && !required_keys.include?([ control, statement ])

        { id: row[:id], control: control }
      end
    end
  end
end
