class SspControlField < ApplicationRecord
  belongs_to :ssp_control
  
  validates :field_name, presence: true
  
  # Define which fields are editable
  EDITABLE_FIELDS = %w[
    responsible_role
    implementation_status
    control_origination
    customer_responsibility
    implementation_guidance
  ].freeze
  
  before_validation :set_editable_flag
  
  private
  
  def set_editable_flag
    self.editable = EDITABLE_FIELDS.include?(field_name)
  end
end