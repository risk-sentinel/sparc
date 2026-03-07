class BoundaryCdefDocument < ApplicationRecord
  belongs_to :boundary
  belongs_to :cdef_document
end
