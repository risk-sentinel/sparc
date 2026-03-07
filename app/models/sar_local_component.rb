class SarLocalComponent < ApplicationRecord
  belongs_to :sar_document

  validates :uuid, presence: true
end
