class Evidence < ApplicationRecord
  has_one_attached :file

  belongs_to :authorization_boundary, optional: true
  has_many :evidence_control_links, dependent: :destroy
  has_many :attestations, dependent: :destroy

  validates :title, presence: true
  validates :evidence_type, presence: true
  validates :status, presence: true

  enum :evidence_type, {
    artifact: "artifact",
    screenshot: "screenshot",
    log: "log",
    config_export: "config_export",
    scan_result: "scan_result",
    signed_statement: "signed_statement",
    policy_document: "policy_document",
    test_result: "test_result"
  }

  enum :status, {
    draft: "draft",
    collected: "collected",
    reviewed: "reviewed",
    attested: "attested",
    expired: "expired"
  }

  EVIDENCE_TYPE_LABELS = {
    "artifact" => "Artifact",
    "screenshot" => "Screenshot",
    "log" => "Log File",
    "config_export" => "Configuration Export",
    "scan_result" => "Scan Result",
    "signed_statement" => "Signed Statement",
    "policy_document" => "Policy Document",
    "test_result" => "Test Result"
  }.freeze

  STATUS_LABELS = {
    "draft" => "Draft",
    "collected" => "Collected",
    "reviewed" => "Reviewed",
    "attested" => "Attested",
    "expired" => "Expired"
  }.freeze

  def type_label
    EVIDENCE_TYPE_LABELS[evidence_type] || evidence_type.titleize
  end

  def status_label
    STATUS_LABELS[status] || status.titleize
  end

  def compute_file_hash!
    return unless file.attached?

    self.file_hash = Digest::SHA256.hexdigest(file.download)
    self.file_content_type = file.content_type
    self.original_filename = file.filename.to_s
    self.file_size = file.byte_size
    save!
  end

  def linked_control_ids
    evidence_control_links.pluck(:control_id).uniq
  end

  def attested?
    attestations.any?
  end
end
