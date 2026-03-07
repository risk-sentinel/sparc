class SspLeveragedAuthorization < ApplicationRecord
  belongs_to :ssp_document

  validates :uuid, presence: true
  validates :title, presence: true
  validates :party_uuid, presence: true
  validates :date_authorized, presence: true
end
