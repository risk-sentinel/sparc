class SspDocumentCdefDocument < ApplicationRecord
  belongs_to :ssp_document
  belongs_to :cdef_document
end
