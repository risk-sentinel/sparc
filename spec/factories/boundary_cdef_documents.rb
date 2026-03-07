FactoryBot.define do
  factory :boundary_cdef_document do
    association :boundary
    association :cdef_document
  end
end
