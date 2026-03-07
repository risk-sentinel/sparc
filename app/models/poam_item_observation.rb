class PoamItemObservation < ApplicationRecord
  belongs_to :poam_item
  belongs_to :poam_observation
end
