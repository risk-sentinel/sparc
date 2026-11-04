# frozen_string_literal: true

# #1328 — every statement part an SSP control requires has a row to answer in.
#
# The editor answers an SSP item by item, one statement row each (#1312), and
# counts the items from ControlRequirementText (#1242). An SSP whose controls
# hold only `<control>_smt` (created before v1.17.4, or imported) showed
# "0/6 answered" and offered nothing but Notes: the items were counted, but no
# row existed to type into. The 2026-09-05 backfill ran once and read the parts
# from a different source, so documents created or imported since, or whose
# baseline names no catalog, kept the old shape.
#
# This adds the rows from the SAME tree the editor and the counts read
# (ControlRequirementText#rows), so what is counted can always be answered.
#
# Additive, never destructive: a row that exists (whatever its case) is left
# alone, prose and all. Nothing is removed. Statement UUIDs are derived the way
# CatalogPartExtractorService derives them (#397), so a row added here has the
# identity the same part would have had if it had been created with the SSP.
#
# NIST SP 800-53 Rev 5: PL-2 (the SSP describes how each requirement is met).
class SspStatementRows
  NAMESPACE = "ssp-statement"

  def self.ensure!(document) = new(document).ensure!

  def initialize(document)
    @document = document
  end

  # @return [Integer] rows added
  def ensure!
    rows = pending_rows
    return 0 if rows.empty?

    # Unique on (ssp_control_id, statement_id): a concurrent run adds nothing twice.
    SspControlStatement.insert_all(rows, unique_by: :idx_ssp_stmt_on_ctrl_sid)
    rows.size
  end

  # #1337 — how many rows #ensure! would add, without adding them.
  def pending_count = pending_rows.size

  private

  def pending_rows
    controls = @document.ssp_controls.where(parent_id: nil).includes(:ssp_control_statements).to_a
    return [] if controls.empty?

    texts = ControlRequirementText.for_profile(@document.profile_document)
                                  .for_controls(controls.map(&:control_id))
    now = Time.current
    controls.flat_map { |control| missing_rows(control, texts[ControlId.canonical(control.control_id)], now) }
  end

  def missing_rows(control, text, now)
    return [] if text.nil? || text.rows.blank?

    have = control.ssp_control_statements.map { _1.statement_id.to_s.downcase }.to_set
    text.rows.each_with_index.filter_map do |row, order|
      next if have.include?(row.part_id.to_s.downcase)

      {
        ssp_control_id: control.id,
        uuid: OscalUuidService.derived(control.uuid, NAMESPACE, row.part_id),
        statement_id: row.part_id,
        label: row.label,
        parent_statement_id: row.parent_part_id,
        row_order: order,
        created_at: now,
        updated_at: now
      }
    end
  end
end
