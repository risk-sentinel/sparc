# Shared batch insert logic for parser services (TPR, Profile, SSP).
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
#       control_class: TprControl,
#       field_class:   TprControlField,
#       document_fk:   :tpr_document_id,
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
  # @param control_class [Class]  ActiveRecord model for controls (e.g. TprControl)
  # @param field_class   [Class]  ActiveRecord model for fields (e.g. TprControlField)
  # @param document_fk   [Symbol] Foreign key column name (e.g. :tpr_document_id)
  # @param control_attrs [Array<Hash>] Attribute hashes for each control
  # @param field_entries [Array<Array>] Triples of [control_index, field_name, field_value]
  # @return [Array<Integer>] IDs of the imported control records
  #
  def batch_insert_records(control_class:, field_class:, document_fk:, control_attrs:, field_entries:)
    control_fk = :"#{control_class.name.underscore}_id"

    ActiveRecord::Base.transaction do
      imported_ids = []

      control_attrs.each_slice(BATCH_SIZE_CONTROLS) do |batch|
        records = batch.map do |attrs|
          control_class.new(document_fk => @document.id, **attrs.compact)
        end
        result = control_class.import(records, validate: false, returning: :id)
        imported_ids.concat(result.ids)
      end

      field_records = field_entries.map do |ctrl_idx, fname, fval|
        field_class.new(
          control_fk => imported_ids[ctrl_idx],
          field_name:    fname,
          field_value:   fval,
          editable:      field_class::EDITABLE_FIELDS.include?(fname)
        )
      end

      field_records.each_slice(BATCH_SIZE_FIELDS) do |batch|
        field_class.import(batch, validate: false)
      end

      imported_ids
    end
  end
end
