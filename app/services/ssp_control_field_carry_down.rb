# frozen_string_literal: true

# #1312 — copies a control's retired control-level answers onto the statement
# items that now hold them, in OSCAL's terms.
#
# Before v1.17.5 an SSP recorded status, control type, responsible entities and
# expected completion once per control. Each item that takes a response (no
# item below it: ac-2 d.1, not the lead-in d.) now records its own. This is the
# one mapping from the old values to the new, used by the upgrade
# (CarrySspControlFieldsToItems) and by the OSCAL importer for a document an
# older SPARC exported.
#
#   status         Implemented → implemented · Deferred → planned ·
#                  Will Not Implement → alternative (owner, 2026-10-27) ·
#                  Not Applicable → not-applicable · OSCAL's own tokens as-is
#   control type   System Specific → system-specific · Inherited from provider →
#                  inherited · Hybrid — partially inherited → left for the
#                  author (which share is inherited is per item), noted ·
#                  Not Applicable → status not-applicable · OSCAL's tokens as-is
#   responsible    each name matching a role the document declares (id or
#   entities       title) → that role; the rest noted
#   expected       an ISO date → the item's date; anything else noted
#   completion
#   control application, coverage level → noted (retired, not OSCAL's)
#
# "Noted" means appended once to the control's `notes`, which the export carries
# in the requirement's remarks, so nothing an author wrote is lost.
#
# An item's own value always wins: only blank item fields are filled. Running
# it twice changes nothing the second time.
class SspControlFieldCarryDown
  NOTE_MARKER = "Carried from the control-level fields (v1.17.5):"

  NOT_APPLICABLE_STATUS = "not-applicable"

  STATUS_MAP = {
    "implemented" => "implemented",
    "deferred" => "planned",
    "planned" => "planned",
    "will not implement" => "alternative",
    "alternative" => "alternative",
    "alternative implementation" => "alternative",
    "not applicable" => NOT_APPLICABLE_STATUS,
    NOT_APPLICABLE_STATUS => NOT_APPLICABLE_STATUS,
    "partially implemented" => "partial",
    "partial" => "partial"
  }.freeze

  ORIGINATION_MAP = {
    "system specific" => [ "system-specific" ],
    "inherited from provider" => [ "inherited" ],
    "inherited" => [ "inherited" ]
  }.merge(SspControlStatement::CONTROL_ORIGINATIONS.to_h { [ _1, [ _1 ] ] }).freeze

  NOT_APPLICABLE = "not applicable"

  Result = Struct.new(:controls, :items, :noted, keyword_init: true)

  def initialize(document)
    @document = document
  end

  def carry!
    result = Result.new(controls: 0, items: 0, noted: 0)
    roles = role_lookup
    @document.ssp_controls.where(parent_id: nil).includes(:ssp_control_fields, :ssp_control_statements).find_each do |control|
      fields = retired_values(control)
      next if fields.empty?

      ActiveRecord::Base.transaction do
        filled, notes = carry_control(control, fields, roles)
        result.controls += 1
        result.items += filled
        result.noted += 1 if note!(control, notes)
      end
    end
    result
  end

  private

  def retired_values(control)
    control.ssp_control_fields
           .select { SspControlField::RETIRED_FIELDS.include?(_1.field_name) && _1.field_value.to_s.strip.present? }
           .to_h { [ _1.field_name, _1.field_value.to_s.strip ] }
  end

  # [items filled, lines to note]
  def carry_control(control, fields, roles)
    notes = []
    status = map_status(fields["status"], notes)
    origination = map_origination(fields["control_type"], notes)
    status ||= NOT_APPLICABLE_STATUS if fields["control_type"].to_s.downcase == NOT_APPLICABLE
    role_refs = map_roles(fields["responsible_entities"], roles, notes)
    date = map_date(fields["expected_completion"], notes)
    %w[control_application coverage_level].each do |name|
      notes << "#{name.tr('_', ' ').capitalize}: #{fields[name]}" if fields[name]
    end

    filled = response_items(control).count do |item|
      fill(item, status: status, origination: origination, roles: role_refs, date: date)
    end
    [ filled, notes ]
  end

  def fill(item, status:, origination:, roles:, date:)
    attrs = {}
    attrs[:implementation_status] = status if status && item.implementation_status.blank?
    attrs[:control_origination] = origination if origination.present? && item.control_origination.blank?
    attrs[:responsible_roles_data] = roles if roles.present? && Array(item.responsible_roles_data).empty?
    attrs[:expected_completion] = date if date && item.expected_completion.nil?
    return false if attrs.empty?

    item.update!(attrs)
    true
  end

  def map_status(value, notes)
    return nil if value.blank?

    STATUS_MAP[value.downcase].tap { |mapped| notes << "Status: #{value}" unless mapped }
  end

  def map_origination(value, notes)
    return nil if value.blank? || value.downcase == NOT_APPLICABLE

    ORIGINATION_MAP[value.downcase].tap do |mapped|
      notes << "Control type: #{value} (set each item's origination)" unless mapped
    end
  end

  def map_roles(value, roles, notes)
    return nil if value.blank?

    names = value.split(/[,;\n]/).map(&:strip).compact_blank
    matched, unmatched = names.partition { roles.key?(_1.downcase) }
    notes << "Responsible entities: #{unmatched.join(', ')}" if unmatched.any?
    matched.map { roles[_1.downcase] }.uniq.map { { "role-id" => _1 } }
  end

  def map_date(value, notes)
    return nil if value.blank?

    Date.iso8601(value)
  rescue Date::Error
    notes << "Expected completion: #{value}"
    nil
  end

  # downcased id or title => role id, for the roles the document declares.
  def role_lookup
    @document.declared_role_options.each_with_object({}) do |(title, id), lookup|
      lookup[id.to_s.downcase] = id
      lookup[title.to_s.downcase] = id
    end
  end

  # The items that take a response: statement rows with no row below them. A
  # control with no rows gets its `_smt`, so its answer has somewhere to live.
  def response_items(control)
    rows = control.ssp_control_statements.to_a
    return [ statement_for_whole(control) ] if rows.empty?

    parents = rows.filter_map(&:parent_statement_id).to_set
    rows.reject { parents.include?(_1.statement_id) }
  end

  def statement_for_whole(control)
    statement_id = "#{ControlId.canonical(control.control_id)}_smt"
    control.ssp_control_statements.create!(
      statement_id: statement_id,
      uuid: OscalUuidService.derived(control.uuid, "ssp-statement", statement_id)
    )
  end

  def note!(control, lines)
    return false if lines.empty?

    field = control.ssp_control_fields.find { _1.field_name == "notes" } ||
            control.ssp_control_fields.build(field_name: "notes")
    return false if field.field_value.to_s.include?(NOTE_MARKER)

    field.field_value = [ field.field_value.presence, "#{NOTE_MARKER}\n#{lines.join("\n")}" ].compact.join("\n\n")
    field.save!
    true
  end
end
