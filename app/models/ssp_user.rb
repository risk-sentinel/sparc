class SspUser < ApplicationRecord
  belongs_to :ssp_document

  validates :uuid, presence: true
end
