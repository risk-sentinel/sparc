class TprControlField < ApplicationRecord
  belongs_to :tpr_control
  
  validates :field_name, presence: true
  
  EDITABLE_FIELDS = %w[
    test_status
    test_date
    tester_name
    test_results
    remediation_plan
  ].freeze
  
  before_validation :set_editable_flag
  
  private
  
  def set_editable_flag
    self.editable = EDITABLE_FIELDS.include?(field_name)
  end
end