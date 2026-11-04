# frozen_string_literal: true

# #1330 — change the baseline an SSP is based on, after its author has seen
# what the change does (owner decisions, 2026-11-03):
#
#   added      controls the new baseline selects that the SSP lacks: created,
#              with a row for every item, ready to answer
#   unchanged  controls in both: kept as they are, answers and all
#   kept       controls the new baseline does not select that have ANY answer:
#              kept, marked `kept_outside_baseline`, left out of the export
#   removed    controls the new baseline does not select with no answer: dropped
#
# A published SSP's baseline stays fixed (CatalogLineage): change a copy. The
# web page and the API both preview with #delta and apply with #apply!, so the
# two cannot disagree about what a change does.
#
# #1337 — "Bring up to baseline" is the same change with the SSP's own
# baseline (SspBaselineChange.fill): it only adds. Controls the baseline
# selects that the SSP lacks are created, with their items, and the items
# missing from controls it already has are added. Nothing that exists is
# changed or removed, and controls outside the baseline are left alone.
#
# NIST SP 800-53 Rev 5: PL-2 (the SSP follows its baseline), CM-3 (the change
# is previewed, confirmed and audited).
class SspBaselineChange
  class Refused < StandardError; end

  Delta = Data.define(:added, :unchanged, :kept, :removed) do
    def to_h = { added: added, unchanged: unchanged, kept: kept, removed: removed }

    def summary = "#{added.size} added, #{kept.size} kept for their answers, #{removed.size} removed"
  end

  # Fields the catalog fills in when the SSP is built; anything else holding a
  # value is something an author (or an import) recorded.
  CATALOG_FIELDS = %w[stated_requirement description].freeze

  STATEMENT_ANSWERS = %i[implementation_prose implementation_status control_origination
                         responsible_roles_data remarks expected_completion].freeze

  attr_reader :document, :profile, :items_added

  def initialize(document, profile, fill_only: false)
    @document = document
    @profile = profile
    @fill_only = fill_only
  end

  # #1337 — bring the SSP up to its own baseline.
  def self.fill(document) = new(document, document.profile_document, fill_only: true)

  def fill_only? = @fill_only

  # #1337 — items (statement rows) the SSP's existing controls lack.
  def missing_items = SspStatementRows.new(document).pending_count

  # #1337 — anything to add: a control, or an item of one the SSP has.
  def needed? = delta.added.any? || missing_items.positive?

  # The baselines an SSP can be moved to: published, with a resolved catalog.
  def self.choices = ProfileDocument.ssp_ready.order(:name)

  # @return [Delta] canonical control ids, in the SSP's or the baseline's order
  def delta
    current = current_controls
    target = target_control_ids
    target_set = target.to_set
    outside = current.keys.reject { target_set.include?(_1) }
    # Filling never touches a control outside the baseline.
    kept, removed = fill_only? ? [ [], [] ] : outside.partition { answered?(current[_1]) }

    Delta.new(added: target.reject { current.key?(_1) }, unchanged: target.select { current.key?(_1) },
              kept: kept, removed: removed)
  end

  # @raise [Refused] when the change cannot be made
  # @return [Delta] what was applied
  def apply!
    refuse_unless_allowed!
    return fill! if fill_only?

    change = delta
    current = current_controls

    ActiveRecord::Base.transaction do
      document.assign_attributes(profile_document: profile)
      document.save!(validate: false) # as BaselineDeclarable: judged on its own rule

      change.removed.each { current[_1].destroy! }
      ids_of(current, change.kept).then { SspControl.where(id: _1).update_all(kept_outside_baseline: true) }
      ids_of(current, change.unchanged).then { SspControl.where(id: _1).update_all(kept_outside_baseline: false) }
      SspFromProfileService.new(profile).add_controls(document, change.added)
      SspStatementRows.ensure!(document)
    end
    change
  end

  # Why the change would be refused, or nil, without applying anything.
  def refusal
    refuse_unless_allowed!
    nil
  rescue Refused => e
    e.message
  end

  def refuse_unless_allowed!
    return refuse_fill_unless_allowed! if fill_only?

    raise Refused, "Choose a baseline." if profile.nil?
    if document.published_lifecycle?
      raise Refused, "This SSP is published and its baseline is fixed. Create a copy to change it."
    end
    raise Refused, "That baseline is not published with a resolved catalog." unless self.class.choices.exists?(id: profile.id)
    raise Refused, "This SSP already uses that baseline." if document.profile_document_id == profile.id
  end

  private

  def refuse_fill_unless_allowed!
    raise Refused, "This SSP has no baseline. Choose one with Change baseline." if profile.nil?
    raise Refused, "This SSP is published and can't be changed. Create a copy to change it." if document.published_lifecycle?
    return if self.class.choices.exists?(id: profile.id)

    raise Refused, "This SSP's baseline is not published with a resolved catalog, so its controls can't be read."
  end

  # Add what is missing; change nothing else. A second run adds nothing.
  def fill!
    change = delta
    ActiveRecord::Base.transaction do
      SspFromProfileService.new(profile).add_controls(document, change.added)
      @items_added = SspStatementRows.ensure!(document)
    end
    change
  end

  # canonical control id => root SspControl
  def current_controls
    @current_controls ||= document.ssp_controls.where(parent_id: nil)
                                  .includes(:ssp_control_fields, :provider_statements,
                                            ssp_control_statements: :inheritance_links)
                                  .order(:row_order, :id)
                                  .index_by { ControlId.canonical(_1.control_id) }
  end

  # The controls an SSP built from this baseline would have, as SSP creation
  # builds them (SspFromProfileService), in catalog order.
  def target_control_ids
    ids = []
    ResolvedCatalog.wrap(profile.resolved_catalog_json).each_control { |control, _group| ids << ControlId.canonical(control["id"]) }
    ids.uniq
  end

  # Anything recorded on the control or its items: a response, a status, an
  # origination, roles, remarks, a date, an inherited or leveraged answer, or a
  # control-level field the catalog did not fill. Conservative by design: when
  # in doubt a control is kept, never dropped.
  def answered?(control)
    return true if control.provider_statements.any?
    return true if control.ssp_control_fields.any? { !CATALOG_FIELDS.include?(_1.field_name) && _1.field_value.present? }

    control.ssp_control_statements.any? do |statement|
      statement.inheritance_links.any? || STATEMENT_ANSWERS.any? { statement.public_send(_1).present? }
    end
  end

  def ids_of(current, control_ids) = control_ids.map { current[_1].id }
end
