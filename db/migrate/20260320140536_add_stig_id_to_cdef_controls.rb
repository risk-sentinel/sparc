class AddStigIdToCdefControls < ActiveRecord::Migration[8.1]
  def change
    add_column :cdef_controls, :stig_id, :string
    add_index :cdef_controls, %i[cdef_document_id stig_id], name: "index_cdef_controls_on_document_and_stig_id"
  end
end
