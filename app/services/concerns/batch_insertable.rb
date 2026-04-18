# Shared batch insert logic for parser services (SAR, Profile, SSP).
#
# Uses activerecord-import to insert controls and fields in batches within
# a single transaction for maximum throughput on large files.
#
# Usage in a parser service:
#   include BatchInsertable
#
#   def parse
#     control_attrs = [ { control_id: "AC-1", title: "...", ... }, ... ]
#     field_entries = [ [0, "result", "Pass"], [0, "notes", "..."], ... ]
#
#     batch_insert_records(
#       control_class: SarControl,
#       field_class:   SarControlField,
#       document_fk:   :sar_document_id,
#       control_attrs: control_attrs,
#       field_entries: field_entries
#     )
#   end
#
module BatchInsertable
  extend ActiveSupport::Concern

  BATCH_SIZE_CONTROLS = 5_000
  BATCH_SIZE_FIELDS   = 10_000

  private

  # Batch-inserts control records and their associated field records.
  #
  # @param control_class [Class]  ActiveRecord model for controls (e.g. SarControl)
  # @param field_class   [Class]  ActiveRecord model for fields (e.g. SarControlField)
  # @param document_fk   [Symbol] Foreign key column name (e.g. :sar_document_id)
  # @param control_attrs [Array<Hash>] Attribute hashes for each control
  # @param field_entries [Array<Array>] Triples of [control_index, field_name, field_value]
  # @return [Array<Integer>] IDs of the imported control records
  #
  def batch_insert_records(control_class:, field_class:, document_fk:, control_attrs:, field_entries:)
    control_fk = :"#{control_class.name.underscore}_id"

    # activerecord-import bypasses the PG `gen_random_uuid()` column default
    # because it builds the INSERT explicitly from listed attribute names.
    # When the target table has a NOT NULL `uuid` column (introduced in #397
    # for OSCAL UUID stability), seed each record with SecureRandom.uuid so
    # the bulk insert satisfies the constraint.
    inject_uuid_for_control = control_class.column_names.include?("uuid")
    inject_uuid_for_field   = field_class.column_names.include?("uuid")

    ActiveRecord::Base.transaction do
      imported_ids = []

      control_attrs.each_slice(BATCH_SIZE_CONTROLS) do |batch|
        records = batch.map do |attrs|
          merged = attrs.compact
          merged[:uuid] ||= SecureRandom.uuid if inject_uuid_for_control
          control_class.new(document_fk => @document.id, **merged)
        end
        result = control_class.import(records, validate: false, returning: :id)
        imported_ids.concat(result.ids)
      end

      field_records = field_entries.map do |ctrl_idx, fname, fval|
        field_attrs = {
          control_fk => imported_ids[ctrl_idx],
          field_name:  fname,
          field_value: fval,
          editable:    field_class::EDITABLE_FIELDS.include?(fname)
        }
        field_attrs[:uuid] = SecureRandom.uuid if inject_uuid_for_field
        field_class.new(field_attrs)
      end

      field_records.each_slice(BATCH_SIZE_FIELDS) do |batch|
        field_class.import(batch, validate: false)
      end

      imported_ids
    end
  end
end
