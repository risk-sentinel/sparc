# Boundary-to-boundary leveraged authorization (#396). The leveraging
# boundary inherits control implementation from the leveraged boundary.
# `leveraged_boundary_id` is nullable to cover Scenarios 2 + 3 where the
# leveraging organization doesn't have access to the leveraged SSP inside
# SPARC and uploads a CRM/SSRM back-matter resource instead.
#
# Per NIST OSCAL Implementation Layers deck slides 15-21:
# - Scenario 1: leveraged SSP is in SPARC, leveraging can read it directly
# - Scenario 2: leveraged SSP is OSCAL but access-restricted → OSCAL CRM
# - Scenario 3: leveraged SSP is legacy (non-OSCAL) → legacy CRM
#
# NIST CA-3: System Interconnections / CA-9: Internal System Connections
class LeveragedAuthorization < ApplicationRecord
  belongs_to :leveraging_boundary, class_name: "AuthorizationBoundary"
  belongs_to :leveraged_boundary, class_name: "AuthorizationBoundary", optional: true
  has_many :leveraged_authorization_components, dependent: :destroy
  has_many :back_matter_resources, as: :resourceable, dependent: :destroy

  CRM_TYPES = %w[oscal_with_access oscal_no_access legacy].freeze

  before_validation :assign_uuid_if_blank

  validates :uuid, presence: true,
                   format: { with: BackMatterResource::UUID_V4_REGEX }
  validates :name, presence: true
  validates :crm_type, inclusion: { in: CRM_TYPES }
  validate  :no_self_reference
  validate  :no_cycle

  # Scenario from the deck: 1 = OSCAL with access, 2 = OSCAL CRM, 3 = legacy.
  def scenario
    case crm_type
    when "oscal_with_access" then 1
    when "oscal_no_access"   then 2
    when "legacy"            then 3
    else nil # crm_type is validated against CRM_TYPES
    end
  end

  # Pull `provided` and `responsibility` statements from the leveraged
  # SSP (Scenario 1 only). The parser round-trips these tags into
  # `set_parameters_data` keyed "provided" / "responsibility" so this
  # query can find them post-import.
  def inheritable_statements
    ssp = leveraged_boundary&.ssp_document
    return SspControlStatement.none unless ssp

    SspControlStatement
      .joins(ssp_control: :ssp_document)
      .where(ssp_controls: { ssp_document_id: ssp.id })
      .where(
        "set_parameters_data::jsonb @> ?::jsonb OR set_parameters_data::jsonb @> ?::jsonb",
        [ { "tag" => "provided" } ].to_json,
        [ { "tag" => "responsibility" } ].to_json
      )
  end

  private

  def assign_uuid_if_blank
    self.uuid = SecureRandom.uuid if uuid.blank?
  end

  def no_self_reference
    return if leveraging_boundary_id.nil? || leveraged_boundary_id.nil?
    if leveraging_boundary_id == leveraged_boundary_id
      errors.add(:leveraged_boundary, "cannot be the same as the leveraging boundary")
    end
  end

  # Walk up the chain to detect cycles. Caps at 64 hops defensively.
  def no_cycle
    return if leveraged_boundary.nil?

    seen = Set.new([ leveraging_boundary_id ])
    current_id = leveraged_boundary_id
    hops = 0
    while current_id && hops < 64
      if seen.include?(current_id)
        errors.add(:leveraged_boundary, "would create a cycle in the leveraged-authorization graph")
        return
      end
      seen << current_id
      current_id = LeveragedAuthorization
                     .where(leveraging_boundary_id: current_id)
                     .pluck(:leveraged_boundary_id)
                     .first
      hops += 1
    end
  end
end
