class SspDocument < ApplicationRecord
  has_many :ssp_controls, dependent: :destroy
  has_one_attached :file

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true
  validates :file_type, inclusion: { in: %w[excel json] }

  def to_json_data
    {
      document_name: name,
      controls: ssp_controls.includes(:ssp_control_fields).map(&:to_hash)
    }
  end

  def self.from_excel(file_path, original_filename)
    document = create!(
      name: File.basename(original_filename, ".*"),
      file_type: "excel",
      original_filename: original_filename,
      status: "processing"
    )

    SspExcelParserService.new(document, file_path).parse
    document.update!(status: "completed")
    document
  rescue StandardError => e
    document&.update!(status: "failed")
    raise e
  end
end
