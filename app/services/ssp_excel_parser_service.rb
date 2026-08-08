require "roo"

class SspExcelParserService
  include BatchInsertable
  include ProgressTrackable

  # Column mapping is loaded from lib/data_mappings/ssp_excel.json via DataMappingSchema.
  # This provides a vendor-neutral, declarative mapping that includes editability,
  # validation rules, and OSCAL export field mappings alongside the import config.
  SCHEMA = DataMappingSchema.load(:ssp_excel)
  COLUMN_MAP = SCHEMA.column_map.freeze

  def initialize(ssp_document, file_path)
    @document  = ssp_document
    @file_path = file_path
    @spreadsheet = Roo::Spreadsheet.open(file_path.to_s)
  end

  def parse
    update_processing_stage!(:reading_file, "Opening spreadsheet...")

    sheet = @spreadsheet.sheet(0)
    return if sheet.last_row.nil? || sheet.last_row < 2

    total_rows = sheet.last_row - 1
    update_processing_stage!(:parsing, "Parsing #{total_rows} rows...")

    raw_headers = sheet.row(1).map { |h| h.to_s.strip.downcase }
    col_config = build_col_config(raw_headers)

    # Collect all rows, tracking parent-child relationships.
    # Rows with control_id are "parents" (root controls).
    # Rows without control_id are "children" (provider statements)
    # belonging to the most recent parent.
    rows              = []
    current_parent_idx = nil
    row_order          = 0
    dropped_rows      = 0

    (2..sheet.last_row).each do |row_num|
      row_data = sheet.row(row_num)
      next if row_data.all?(&:nil?)

      attrs  = {}
      fields = {}

      col_config.each do |idx, config|
        raw   = row_data[idx]
        value = raw.nil? ? nil : raw.to_s.strip.presence

        if config[:control_attr]
          attrs[config[:key]] = value
        else
          fields[config[:key]] = value unless value.nil?
        end
      end

      # #913 — a row with NO control id is not a control.
      #
      # In a spreadsheet SSP these blank rows are continuation lines: what OSCAL
      # models as a LEVERAGED SSP, not as a control of this system. Importing
      # them as headless `SspControl` rows produced records with no control_id
      # and no derived family, which is what made
      # `control_id.to_s.split("-").first.upcase` raise across the app — the
      # blank state was manufactured here and guarded against everywhere else.
      #
      # Dropping them removes the state at its source. The rows carry prose, so
      # this is a lossy import: it is a MIGRATION AID for converting a
      # spreadsheet into a real OSCAL SSP, which a human then enriches. The
      # count is recorded on the document so the loss is visible rather than
      # silent.
      #
      # This is NOT a retreat from #911's ruling 8 ("never drop a row; alert").
      # That governs a row whose control id is UNRECOGNISED — a control the
      # author intended to claim, which must still be reported and never
      # discarded. A row with no control id was never a control claim.
      unless attrs[:control_id].present?
        dropped_rows += 1
        next
      end

      is_parent  = true
      parent_ref = nil
      current_parent_idx = rows.size

      rows << {
        attrs:      { control_id: attrs[:control_id].presence, title: attrs[:title], row_order: row_order },
        fields:     fields,
        is_parent:  is_parent,
        parent_ref: parent_ref
      }
      # Progress heartbeat every 500 rows
      if row_order > 0 && (row_order % 500).zero?
        update_processing_progress!("Parsed #{row_order} of #{total_rows} rows...")
      end

      row_order += 1
    end

    record_dropped_rows!(dropped_rows)

    update_processing_stage!(:creating_records, "Creating #{rows.size} controls in database...")
    batch_insert_with_hierarchy(rows)
    update_processing_stage!(:finalizing, "Finalizing #{rows.size} controls...")
  end

  private

  # #913 — a lossy import must say what it dropped. Recorded on the document
  # rather than only logged, so the number survives the request and an author
  # can see it when they come to enrich the result.
  def record_dropped_rows!(count)
    return if count.zero?

    @document.update_columns(
      import_metadata: (@document.import_metadata || {}).merge(
        "dropped_rows_without_control_id" => count
      )
    )
  end

  # Two-phase batch insert: parents first (to get their IDs), then children
  # with parent_id resolved, then all fields.
  def batch_insert_with_hierarchy(rows)
    return if rows.empty?

    parents  = []
    children = []

    rows.each_with_index do |row, idx|
      entry = { original_idx: idx, attrs: row[:attrs], fields: row[:fields] }
      if row[:is_parent]
        parents << entry
      else
        children << entry.merge(parent_ref: row[:parent_ref])
      end
    end

    ActiveRecord::Base.transaction do
      # Phase 1 — batch insert parent controls
      parent_db_ids = {}
      parent_attrs  = parents.map { |p| p[:attrs] }

      parent_attrs.each_slice(BATCH_SIZE_CONTROLS) do |batch|
        # #911/#913 — this parser has its OWN two-phase import and therefore
        # never went through `batch_insert_records`, so the canonicalisation
        # fix applied there missed it entirely: SSP controls imported from a
        # spreadsheet were stored exactly as typed ("AC-1", "AC-02"), which is
        # the very mismatch #911 exists to remove. Route them through the same
        # single declaration rather than normalising inline.
        records = batch.map do |a|
          canonicalise_control_ids(
            SspControl, SspControl.new(ssp_document_id: @document.id, uuid: SecureRandom.uuid, **a.compact)
          )
        end
        result  = SspControl.import(records, validate: false, returning: :id)

        batch_offset = parent_db_ids.size
        result.ids.each_with_index do |db_id, i|
          parent_db_ids[parents[batch_offset + i][:original_idx]] = db_id
        end
      end

      # Phase 2 — batch insert child controls with parent_id resolved
      child_db_ids  = {}
      child_attrs   = children.map do |c|
        resolved_parent_id = c[:parent_ref] ? parent_db_ids[c[:parent_ref]] : nil
        c[:attrs].merge(parent_id: resolved_parent_id)
      end

      child_attrs.each_slice(BATCH_SIZE_CONTROLS) do |batch|
        # #911/#913 — this parser has its OWN two-phase import and therefore
        # never went through `batch_insert_records`, so the canonicalisation
        # fix applied there missed it entirely: SSP controls imported from a
        # spreadsheet were stored exactly as typed ("AC-1", "AC-02"), which is
        # the very mismatch #911 exists to remove. Route them through the same
        # single declaration rather than normalising inline.
        records = batch.map do |a|
          canonicalise_control_ids(
            SspControl, SspControl.new(ssp_document_id: @document.id, uuid: SecureRandom.uuid, **a.compact)
          )
        end
        result  = SspControl.import(records, validate: false, returning: :id)

        batch_offset = child_db_ids.size
        result.ids.each_with_index do |db_id, i|
          child_db_ids[children[batch_offset + i][:original_idx]] = db_id
        end
      end

      # Phase 3 — batch insert all fields
      all_ids = parent_db_ids.merge(child_db_ids)

      field_records = []
      rows.each_with_index do |row, idx|
        control_db_id = all_ids[idx]
        row[:fields].each do |fname, fval|
          field_records << SspControlField.new(
            ssp_control_id: control_db_id,
            field_name:     fname.to_s,
            field_value:    fval,
            editable:       SspControlField::EDITABLE_FIELDS.include?(fname.to_s)
          )
        end
      end

      field_records.each_slice(BATCH_SIZE_FIELDS) do |batch|
        SspControlField.import(batch, validate: false)
      end
    end
  end

  def build_col_config(raw_headers)
    config = {}
    raw_headers.each_with_index do |header, idx|
      mapping = COLUMN_MAP[header]
      config[idx] = mapping if mapping
    end
    config
  end
end
