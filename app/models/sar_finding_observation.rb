class SarFindingObservation < ApplicationRecord
  belongs_to :sar_finding
  belongs_to :sar_observation
end
