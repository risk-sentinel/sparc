class SarRiskObservation < ApplicationRecord
  belongs_to :sar_risk
  belongs_to :sar_observation
end
