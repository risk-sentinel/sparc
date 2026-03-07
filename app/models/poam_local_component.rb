class PoamLocalComponent < ApplicationRecord
  belongs_to :poam_document

  validates :uuid, presence: true
end
