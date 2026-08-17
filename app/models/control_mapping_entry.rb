# frozen_string_literal: true

# Represents a single mapping entry (map) within an OSCAL Control Mapping
# Collection — a relationship between a source control/statement and a
# target control/statement.
#
# Relationship types are aligned with NIST IR 8477 set-theory mapping:
#   equal, equivalent, subset, superset, intersects
class ControlMappingEntry < ApplicationRecord
  include ControlIdentifiable
  # #911 — TARGET only. `source_control_id` is by definition the non-NIST side
  # of the mapping: a FedRAMP KSI entry stores `ksi-iam-01` here and the NIST
  # control in `target_control_id`. `ControlId.canonical` encodes NIST numbering,
  # so it strips KSI's zero-padding to `ksi-iam-1` — an identifier the KSI
  # catalog does not contain, which silently emptied the mappings endpoint.
  #
  # The source identifier persists exactly as it arrived; the NIST side is the
  # one that has to line up with a catalog. Promoting that split into
  # first-class columns across the control-bearing models is #912.
  canonicalises_control_id :target_control_id

  belongs_to :control_mapping, touch: true

  before_validation :generate_uuid, on: :create

  validates :uuid, presence: true, uniqueness: true
  validates :source_control_id, presence: true
  validates :target_control_id, presence: true
  validates :relationship, presence: true,
            inclusion: { in: %w[equal equivalent subset superset intersects] }
  validates :source_type, inclusion: { in: %w[control statement] }
  validates :target_type, inclusion: { in: %w[control statement] }
  validates :source_control_id, uniqueness: {
    scope: [ :control_mapping_id, :target_control_id ],
    message: "to target pair already exists in this mapping"
  }

  default_scope { order(:row_order) }

  RELATIONSHIPS  = %w[equal equivalent subset superset intersects].freeze
  SUBJECT_TYPES  = %w[control statement].freeze

  # #945 — an entry must name controls that exist in the catalogs the mapping
  # points at.
  #
  # Both catalogs are already chosen and SPARC already holds every control in
  # them, and it still accepted a typed identifier no one checked. `AC-2(1)`,
  # `ac-2.1` and `AC-02(01)` are all plausible spellings of the same thing, and
  # a stale or foreign id looked identical to a correct one in the table — then
  # flowed into `download_oscal`, so an unusable mapping reached a consumer that
  # trusted it.
  #
  # Validated on the MODEL, not the form, so `Api::V1` is guarded by the same
  # rule. A controller-side check would have covered one of the two surfaces,
  # which is the drift #919 spent a PR closing.
  validate :source_control_resolves, if: :should_validate_source?
  validate :target_control_resolves, if: :should_validate_target?

  # Does this identifier name something in that catalog?
  #
  # Tries the identifier verbatim FIRST. `ControlId.canonical` encodes NIST
  # numbering, and the source side of a mapping is by definition the non-NIST
  # one — a FedRAMP KSI entry stores `ksi-iam-01`, which canonicalises to
  # `ksi-iam-1`, an identifier the KSI catalog does not contain (#911). So a
  # verbatim hit is authoritative and canonicalisation is only a fallback for
  # the NIST-shaped side.
  #
  # Statement sub-parts resolve through the same lookup because #941 stores them
  # as CatalogControl rows ("ac-1a"), so `statement` subjects are reachable
  # without a second code path.
  def self.resolves?(catalog, identifier)
    return false if catalog.nil? || identifier.blank?

    scope = catalog_scope(catalog)

    # A catalog with no controls loaded cannot answer the question. Refusing
    # every entry against it would make a mapping unusable until someone
    # imported the catalog's contents — the same trap #911 avoided by reporting
    # an unresolved lineage rather than blocking on it. Nothing to check against
    # is not the same as a failed check.
    return true if scope.empty?

    return true if scope.exists?(control_id: identifier)

    # `find_by_canonical` compares against the STORED canonical form, so the
    # input has to be canonicalised too — otherwise "AC-1" never matches the
    # "ac-1" the catalog holds, and the fallback only ever succeeded for
    # identifiers that were already canonical.
    CatalogControl.find_by_canonical(catalog, ControlId.canonical(identifier)).present?
  end

  def self.catalog_scope(catalog)
    CatalogControl.unscoped
                  .joins(control_family: :control_catalog)
                  .where(control_families: { control_catalog_id: catalog.id })
  end

  # Entries stored before this validation existed may not resolve. Reported,
  # never rewritten: a mapping is a record of judgement, and guessing at what
  # someone meant would destroy the thing being recorded.
  def resolved?
    self.class.resolves?(control_mapping&.source_catalog, source_control_id) &&
      self.class.resolves?(control_mapping&.target_catalog, target_control_id)
  end

  def unresolved_sides
    sides = []
    sides << "source" unless self.class.resolves?(control_mapping&.source_catalog, source_control_id)
    sides << "target" unless self.class.resolves?(control_mapping&.target_catalog, target_control_id)
    sides
  end

  private

  # Only when the identifier is being written. An existing row that does not
  # resolve must stay editable — otherwise a legacy entry could never have its
  # remarks corrected, and the record would be frozen by a rule added after it.
  def should_validate_source? = new_record? || source_control_id_changed?
  def should_validate_target? = new_record? || target_control_id_changed?

  def source_control_resolves
    catalog = control_mapping&.source_catalog
    return if catalog.nil? || source_control_id.blank?
    return if self.class.resolves?(catalog, source_control_id)

    errors.add(:source_control_id,
               "is not a control in #{catalog.name}")
  end

  def target_control_resolves
    catalog = control_mapping&.target_catalog
    return if catalog.nil? || target_control_id.blank?
    return if self.class.resolves?(catalog, target_control_id)

    errors.add(:target_control_id,
               "is not a control in #{catalog.name}")
  end

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
