class PoamItemRisk < ApplicationRecord
  belongs_to :poam_item
  belongs_to :poam_risk
end
