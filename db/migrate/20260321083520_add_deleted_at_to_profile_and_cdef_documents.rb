class AddDeletedAtToProfileAndCdefDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :profile_documents, :deleted_at, :datetime
    add_column :cdef_documents, :deleted_at, :datetime

    add_index :profile_documents, :deleted_at
    add_index :cdef_documents, :deleted_at
  end
end
