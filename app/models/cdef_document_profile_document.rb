# frozen_string_literal: true

# #1089 — one baseline a component definition is used under. A CDEF describes
# a component (a database, a load balancer, an OS build) and the controls it
# satisfies, so the same CDEF serves any number of baselines.
class CdefDocumentProfileDocument < ApplicationRecord
  belongs_to :cdef_document
  belongs_to :profile_document

  validates :profile_document_id, uniqueness: { scope: :cdef_document_id }
end
