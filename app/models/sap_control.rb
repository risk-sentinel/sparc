class SapControl < ApplicationRecord
  IN_PROGRESS = "in-progress".freeze

  belongs_to :sap_document
  has_many :sap_control_fields, dependent: :delete_all
  has_many :sap_control_objectives, dependent: :delete_all
  has_many :control_back_matter_links, as: :linkable, dependent: :destroy
  has_many :back_matter_resources, through: :control_back_matter_links

  validates :control_id, presence: true

  before_save :compute_control_family

  ASSESSMENT_METHODS = %w[examine interview test].freeze
  ASSESSMENT_STATUSES = %w[planned in-progress completed].freeze

  # Returns assessment methods as an array. Stored comma-separated in
  # the assessment_method column (e.g. "examine,interview" for controls
  # that require multiple assessment methods).
  def assessment_methods
    return [] if assessment_method.blank?
    assessment_method.to_s.split(",").map { |m| m.strip.downcase }.reject(&:blank?).uniq
  end

  def multiple_methods?
    assessment_methods.size > 1
  end

  # Computed status derived from this control's objectives. Returns one of
  # the new objective vocabulary values (pending/in-progress/passing/failed/
  # not_assessed). This is independent of `assessment_status` (legacy
  # planned/in-progress/completed) so chip filters and historical data keep
  # working until a separate cleanup PR migrates the column entirely.
  #
  # Precedence: failed beats in-progress -- a failed objective is a finding
  # regardless of other objectives in flight. not_applicable doesn't block
  # passing.
  def objective_status_rollup(statuses = sap_control_objectives.pluck(:status))
    return "not_assessed" if statuses.empty? || statuses.all?(&:nil?)
    return "failed"       if statuses.include?("failed")
    return IN_PROGRESS  if statuses.include?(IN_PROGRESS)
    return "pending"      if statuses.any? { |s| %w[pending planned].include?(s) }
    return "passing"      if statuses.all? { |s| %w[passing not_applicable].include?(s) }
    IN_PROGRESS
  end

  def objectives_count
    sap_control_objectives.size
  end

  def objectives_passing_count
    sap_control_objectives.passing.count
  end

  # Returns joined objective prose if discrete objective records exist;
  # otherwise the legacy `objective` text column. Lets the show view and
  # exporters use one accessor regardless of which storage form a SAP uses.
  def aggregate_objective_text
    return objective if sap_control_objectives.empty?
    sap_control_objectives.order(:row_order).map do |obj|
      label = obj.label.presence || obj.objective_id
      "[#{label}] #{obj.prose}".strip
    end.join("\n\n")
  end

  def to_hash
    {
      control_id: control_id,
      title: title,
      control_family: control_family,
      assessment_method: assessment_method,
      assessment_status: assessment_status,
      assessor_name: assessor_name,
      objective: objective,
      test_case: test_case,
      row_order: row_order,
      fields: sap_control_fields.map do |field|
        {
          field_name: field.field_name,
          field_value: field.field_value,
          editable: field.editable
        }
      end
    }
  end

  private

  def compute_control_family
    return if control_family.present?
    self.control_family = control_id.to_s.split("-").first.upcase.presence
  end
end
