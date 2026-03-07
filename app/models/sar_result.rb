class SarResult < ApplicationRecord
  belongs_to :sar_document

  has_many :sar_observations, dependent: :delete_all
  has_many :sar_findings, dependent: :delete_all
  has_many :sar_risks, dependent: :delete_all

  validates :uuid, presence: true
  validates :start_time, presence: true
end
