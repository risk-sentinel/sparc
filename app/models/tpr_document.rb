class TprDocument < ApplicationRecord
  has_many :tpr_controls, dependent: :destroy
  has_one_attached :file
  
  enum status: { pending: 'pending', processing: 'processing', completed: 'completed', failed: 'failed' }
  
  validates :name, presence: true
  validates :file_type, inclusion: { in: %w[excel json] }
  
  def to_json_data
    {
      document_name: name,
      controls: tpr_controls.includes(:tpr_control_fields).map(&:to_hash)
    }
  end
end