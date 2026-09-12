class AuthorizationBoundary < ApplicationRecord
  include Sluggable
  include Searchable
  # #629 — block deletion when assessment/authorization documents are attached
  # (SSP/SAP/SAR/POA&M). Included before the `dependent:` associations so the
  # guard's before_destroy runs first and aborts before any nullify fires.
  include SafeDestroyable
  belongs_to :organization, optional: true
  belongs_to :profile_document, optional: true   # #395 P3: one baseline per system
  has_many :boundaries, dependent: :destroy
  has_many :authorization_boundary_memberships, dependent: :destroy
  has_many :user_roles, dependent: :destroy
  has_many :assigned_users, through: :user_roles, source: :user
  has_many :cdef_documents, through: :boundaries

  # #940 S3 — the information types that DETERMINE this boundary's FIPS-199
  # categorization. Inputs to the categorization, so they belong with it.
  has_many :information_types, class_name: "SspInformationType", dependent: :nullify

  has_one  :ssp_document, dependent: :nullify
  has_one  :sap_document, dependent: :nullify
  has_one  :sar_document, dependent: :nullify
  has_many :poam_documents, dependent: :nullify
  has_many :evidences, dependent: :nullify
  has_many :ksi_validations, dependent: :destroy

  # #447 — HDF Amendment triage layer, boundary-scoped.
  has_many :scan_runs, dependent: :destroy
  has_many :scanner_findings, dependent: :destroy
  has_many :finding_dispositions, dependent: :destroy
  has_many :risk_assessments, dependent: :destroy

  # #396: boundary-level leveraged-authorization graph. `leveraging_relationships`
  # = this boundary leverages other systems. `leveraged_relationships` = other
  # boundaries leverage this one (downstream consumers).
  has_many :leveraging_relationships, class_name: "LeveragedAuthorization",
           foreign_key: :leveraging_boundary_id, dependent: :destroy
  has_many :leveraged_relationships, class_name: "LeveragedAuthorization",
           foreign_key: :leveraged_boundary_id, dependent: :nullify

  enum :status, {
    draft: "draft",
    active: "active",
    authorized: "authorized",
    deauthorized: "deauthorized"
  }

  # #395 P3: the uuid column has a gen_random_uuid() default at the DB
  # level, but validations run before the INSERT populates it. Fill the
  # UUID on before_validation so v4 format validation passes on create.
  before_validation :assign_uuid_if_blank

  validates :name, presence: true
  # Only on the transition INTO `authorized`: an already-authorized boundary
  # whose ISSO leaves must remain editable, or the gate would trap records it
  # was meant to protect.
  validate :staffed_before_authorization, if: -> { status_changed? && authorized? }
  validates :status, presence: true
  validates :uuid, presence: true,
                   format: { with: BackMatterResource::UUID_V4_REGEX }

  STATUSES = %w[draft active authorized deauthorized].freeze

  # #395 P3: single source of truth for system-level metadata. Documents
  # read these via BoundaryMetadataSyncService at edit/render time. Each
  # key maps to a setter on the document side via FIELD_TO_SETTER.
  BOUNDARY_METADATA_KEYS = %w[
    system_title short_name impact_level
    authorization_date authorization_status
    authorizing_official system_owner isso issm assessor
  ].freeze

  BOUNDARY_METADATA_KEYS.each do |key|
    define_method(key) { (boundary_metadata || {})[key] }
    define_method("#{key}=") { |v|
      self.boundary_metadata = (boundary_metadata || {}).merge(key => v)
    }
  end

  # ── FIPS-199 categorization (#940 S3) ──────────────────────────────────
  #
  # The chain NIST actually defines, which SPARC had the pieces of and never
  # assembled:
  #
  #   SP 800-60 Vol 2 gives each information type PROVISIONAL C/I/A impacts
  #     -> the system owner ADJUSTS them, with rationale
  #       -> FIPS-199 takes the HIGH WATER MARK across every type and objective
  #         -> that level selects the 800-53 baseline
  #
  # Nothing computed the high water mark before this. `security_sensitivity_level`
  # was free text set by the wizard or by an OSCAL import, so it could contradict
  # the information types beneath it and nothing checked. Deriving it means the
  # categorization cannot disagree with its own inputs.
  OBJECTIVES = %i[confidentiality integrity availability].freeze

  # The impact for one objective: the high water mark across the information
  # types, falling back to the value recorded directly on the boundary when no
  # type carries one.
  def security_objective(objective)
    from_types = information_types.filter_map { |t| t.effective_impact(objective) }
    highest(from_types).presence || self[:"security_objective_#{objective}"].presence
  end

  # FIPS-199: the system's categorization is the highest impact across all three
  # objectives. One HIGH anywhere makes the system HIGH — that is the rule, and
  # it is why averaging or "mostly moderate" is wrong.
  def security_categorization
    highest(OBJECTIVES.filter_map { |o| security_objective(o) })
  end

  # True when the recorded categorization disagrees with what the information
  # types imply. The condition that was previously undetectable.
  def categorization_conflicts_with_information_types?
    derived = highest(information_types.flat_map { |t| OBJECTIVES.filter_map { |o| t.effective_impact(o) } })
    return false if derived.blank?

    stored = OBJECTIVES.filter_map { |o| self[:"security_objective_#{o}"].presence }
    return false if stored.empty?

    highest(stored) != derived
  end

  private def highest(levels)
    order = SspInformationType::IMPACT_LEVELS
    Array(levels).compact_blank.max_by { |l| order.index(l) || -1 }
  end

  # ── Staffing gate for authorization (#1040) ────────────────────────────
  #
  # A boundary with ZERO members was valid, could reach `status: authorized`,
  # and would export an SSP. SPARC already believed in separation of duties at
  # the moment of an ACTION — a non-admin cannot approve what they submitted,
  # the person who set a disposition cannot approve it, an assessor is denied
  # `evidence.attest` — and was silent about it at the moment of STAFFING.
  #
  # #1040 called this blocked on "two competing rosters". Measured, they are not
  # competing; they answer different questions:
  #
  #   AuthorizationBoundaryMembership / user_roles
  #     WHO MAY ACT in SPARC. Access control. This is the roster.
  #   boundary_metadata[:authorizing_official, …]
  #     WHOSE NAME IS PRINTED in the OSCAL document — propagated into
  #     `authorizing_official_data` and friends by BoundaryMetadataSyncService.
  #     That person may hold no SPARC account at all.
  #
  # They share role names, which is what made them look like rivals. The gate
  # reads the ROSTER, because authorization is about who is accountable, not
  # about what a document says.
  REQUIRED_ROLES_FOR_AUTHORIZATION = %w[authorizing_official system_owner isso].freeze

  # Roles held on the roster, from BOTH assignment paths — admin-assigned
  # user_roles and boundary memberships. Reading only one is how a person added
  # through the other becomes invisible (#770 bug 3).
  def staffed_roles
    # `map`, NOT `pluck`. pluck issues a query and therefore CANNOT SEE
    # memberships built in memory but not yet saved — so staffing a boundary and
    # authorizing it in the same save would fail spuriously, which is exactly
    # what a caller would naturally write. Its own factory trait caught this.
    (authorization_boundary_memberships.map(&:role) +
      user_roles.filter_map { |ur| ur.role&.name }).compact.uniq
  end

  def missing_roles_for_authorization
    REQUIRED_ROLES_FOR_AUTHORIZATION - staffed_roles
  end

  def staffed_for_authorization? = missing_roles_for_authorization.empty?

  def linked_documents
    [ ssp_document, sap_document, sar_document, profile_document, *poam_documents ].compact
  end

  # Other boundaries this boundary inherits from (upstream systems).
  def leveraged_boundaries
    leveraging_relationships.includes(:leveraged_boundary).filter_map(&:leveraged_boundary)
  end

  # Boundaries that inherit from this boundary (downstream consumers).
  def leveraging_boundaries
    leveraged_relationships.includes(:leveraging_boundary).filter_map(&:leveraging_boundary)
  end

  def metadata_drift_for(document)
    BoundaryMetadataSyncService.new(self).drift_for(document)
  end

  def metadata_status_for(document)
    BoundaryMetadataSyncService.new(self).status_for(document)
  end

  def artifact_summary
    {
      ssp: ssp_document&.name,
      sap: sap_document&.name,
      sar: sar_document&.name,
      poam_count: poam_documents.count,
      boundary_count: boundaries.count,
      component_count: boundaries.joins(:cdef_documents).count
    }
  end

  def members_by_role
    authorization_boundary_memberships.order(:role, :user_name).group_by(&:role)
  end

  # #770 bug 3 — unified personnel roster.
  #
  # Personnel live in two systems on the same boundary (AC-3 access records):
  #   - user_roles: canonical Role-catalog assignments. The admin screen's
  #     "Add Member" writes here.
  #   - authorization_boundary_memberships: legacy string-role personnel. The
  #     boundary screen's own "Add Member" writes here.
  #
  # The boundary screen previously read only the legacy table, so anyone added
  # through admin was invisible here. This normalizes both into one list so the
  # roster reflects every assignment regardless of where it was made. Canonical
  # (user_role) entries are managed in admin and render read-only here; legacy
  # entries keep their inline edit/remove.
  PersonnelEntry = Struct.new(:name, :email, :role_label, :source, :membership, keyword_init: true)

  def personnel_roster
    canonical = user_roles.includes(:user, :role).map do |ur|
      PersonnelEntry.new(
        name: ur.user.display_label, email: ur.user.email,
        role_label: ur.role.display_name, source: :assigned, membership: nil
      )
    end
    legacy = authorization_boundary_memberships.order(:role, :user_name).map do |m|
      PersonnelEntry.new(
        name: m.user_name, email: m.user_email,
        role_label: m.role_label, source: :membership, membership: m
      )
    end
    (canonical + legacy).sort_by { |e| [ e.role_label.to_s, e.name.to_s ] }
  end

  private

  # #629 — referential-integrity guard. A boundary cannot be deleted while it
  # still anchors a system's assessment/authorization documents. Members,
  # environments, user-roles and KSI validations continue to cascade.
  def deletion_dependencies
    deps = []
    ssp_count = SspDocument.where(authorization_boundary_id: id).count
    deps << "#{ssp_count} SSP(s)" if ssp_count > 0
    sap_count = SapDocument.where(authorization_boundary_id: id).count
    deps << "#{sap_count} Assessment Plan(s)" if sap_count > 0
    sar_count = SarDocument.where(authorization_boundary_id: id).count
    deps << "#{sar_count} Assessment Result(s)" if sar_count > 0
    poam_count = PoamDocument.where(authorization_boundary_id: id).count
    deps << "#{poam_count} POA&M(s)" if poam_count > 0
    deps
  end

  def staffed_before_authorization
    missing = missing_roles_for_authorization
    return if missing.empty?

    errors.add(:status,
               "cannot be authorized without #{missing.map { |r| r.humanize.titleize }.to_sentence} " \
               "on the personnel roster — authorization records who is accountable")
  end

  def assign_uuid_if_blank
    self.uuid = SecureRandom.uuid if uuid.blank?
  end
end
