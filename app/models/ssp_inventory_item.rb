class SspInventoryItem < ApplicationRecord
  belongs_to :ssp_document

  validates :uuid, presence: true
  validates :description, presence: true
end
