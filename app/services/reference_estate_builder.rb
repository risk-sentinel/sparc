# frozen_string_literal: true

# #845 — builds the reference two-boundary leveraged authorization estate:
# a complete, inspectable authorization chain that exists so tests, demos and
# scanners have something real to work against instead of a handful of
# disconnected fixtures.
#
#   Org A → Boundary 1 (leveraged)   ─┐
#                                      ├─ LeveragedAuthorization (scenario 1)
#   Org B → Boundary 2 (leveraging)  ─┘
#
# Each boundary gets the full chain:
#   Catalog → Profile → SSP → SAP → SAR → three POA&Ms → Evidence
#
# ── Why one builder and not two ────────────────────────────────────────────
#
# Both tiers run the SAME code path, differing only in which control ids they
# are handed. Two builders would drift, and the lean tier would stop being a
# faithful small version of the full one — which is the only thing that makes
# it trustworthy as the suite default.
#
#   :lean — 40 curated controls (LEAN_CONTROL_IDS). The default. Chosen, not
#           sampled: every family is represented and the set deliberately
#           includes controls with parameters, with sub-part rows, and the
#           known-awkward ones (ac-2 has no catalog statement at all, ac-20
#           carries a `select` parameter whose choices are insert references).
#   :full — the real NIST baselines: MODERATE (287) for the leveraged platform
#           that provides, LOW (149) for the leveraging system that consumes.
#           The provider carries the higher baseline because inheritance only
#           flows downward — see leveraged_spec.
#
# ── Not for production ─────────────────────────────────────────────────────
#
# This writes organizations, boundaries and authorization documents that look
# real. `build` refuses to run in production rather than trusting the caller.
class ReferenceEstateBuilder
  class UnsafeEnvironment < StandardError; end
  class MissingCatalog < StandardError; end

  TIERS = %i[lean full].freeze

  # Owner-approved 2026-08-14. All 20 families, ~173 parameters, ~109 sub-part
  # rows in scope. See the issue for why each one earns its place.
  LEAN_CONTROL_IDS = %w[
    ac-1 ac-2 ac-3 ac-6 ac-17 ac-20 at-2 au-1 au-2 au-6 au-9 ca-1 ca-2 ca-5 ca-7
    cm-1 cm-2 cm-6 cp-9 ia-2 ia-5 ir-1 ir-4 ma-2 mp-2 pe-3 pl-2 pm-1 ps-3 pt-2
    ra-1 ra-5 sa-4 sa-9 sc-7 sc-13 si-1 si-2 si-4 sr-3
  ].freeze

  BASELINE_FIXTURE = "spec/fixtures/files/profiles/NIST_SP-800-53_rev5_%s-baseline_profile.json"

  # Everything time-dependent is pinned. An SLA-derived deadline is
  # Time.current-relative, so leaving these to resolve at build time would put
  # a fresh diff in every regeneration of the committed OSCAL.
  PINNED_DEADLINE   = Time.utc(2030, 1, 1)
  PINNED_ASSESSMENT = { start: Time.utc(2026, 1, 5), end: Time.utc(2026, 3, 27) }.freeze

  # The controls Boundary 1 declares it operates on its customers' behalf.
  # Chosen because they are genuinely platform-level in a real leveraging
  # relationship — physical access, boundary protection, audit storage.
  PROVIDED_CONTROL_IDS = %w[pe-3 sc-7 au-9 cp-9 ma-2].freeze

  # ...and the ones it explicitly hands back to the customer. sa-9 and ac-20
  # are the external-services pair, which is exactly the seam a leveraging
  # system has to address itself.
  RESPONSIBILITY_CONTROL_IDS = %w[sa-9 ac-20 ia-5].freeze

  Result = Struct.new(:tier, :leveraged, :leveraging, :inheritance_links, keyword_init: true) do
    def to_s
      "tier=#{tier} leveraged=#{leveraged[:boundary].name.inspect} " \
        "leveraging=#{leveraging[:boundary].name.inspect} links=#{inheritance_links}"
    end
  end

  def initialize(tier: :lean, catalog: nil, actor: nil)
    @tier    = tier.to_sym
    @catalog = catalog
    @actor   = actor

    raise ArgumentError, "unknown tier #{tier.inspect}, expected one of #{TIERS.inspect}" unless TIERS.include?(@tier)
  end

  def build
    refuse_in_production!

    leveraged  = build_boundary(**leveraged_spec)
    leveraging = build_boundary(**leveraging_spec)

    declare_customer_responsibility_split(leveraged)
    links = wire_leveraging(leveraged: leveraged, leveraging: leveraging)

    Result.new(tier: @tier, leveraged: leveraged, leveraging: leveraging, inheritance_links: links)
  end

  private

  # A reference estate is indistinguishable from real authorization data once
  # it is in a database — same models, same screens, same exports. Refusing
  # here is cheaper than explaining it later.
  def refuse_in_production!
    return unless Rails.env.production?

    raise UnsafeEnvironment,
          "ReferenceEstateBuilder will not run in production — it creates authorization " \
          "documents that are indistinguishable from real ones."
  end

  # `leveraged` is the boundary being consumed — the platform that PROVIDES
  # control implementation. `leveraging` is the boundary consuming it. The
  # model states the direction outright: "the leveraging boundary inherits
  # control implementation from the leveraged boundary", and the service reads
  # inheritable_statements from leveraged_boundary while writing to
  # leveraging_boundary.
  #
  # So the PROVIDER carries the higher baseline. A system cannot inherit a
  # control its platform was never assessed against, and MODERATE is a strict
  # superset of LOW (measured: 0 LOW controls absent from MODERATE, 138 added).
  # Handing the provider LOW and the consumer MODERATE would leave 138 controls
  # on the consumer that no amount of configuration could ever satisfy.
  def leveraged_spec
    {
      role:          :leveraged,
      org_name:      "Reference Platform Provider (Org A)",
      boundary_name: "Reference Platform (Boundary 1)",
      control_ids:   @tier == :lean ? LEAN_CONTROL_IDS : baseline_control_ids("MODERATE"),
      baseline:      "moderate"
    }
  end

  def leveraging_spec
    {
      role:          :leveraging,
      org_name:      "Reference Mission System Owner (Org B)",
      boundary_name: "Reference Mission System (Boundary 2)",
      control_ids:   @tier == :lean ? LEAN_CONTROL_IDS : baseline_control_ids("LOW"),
      baseline:      @tier == :lean ? "moderate" : "low"
    }
  end

  # The NIST baselines ship as OSCAL profile fixtures; the catalog itself
  # carries no baseline_impact for Rev 5 (measured: nil on all 2318 rows), so
  # membership has to come from the profile.
  def baseline_control_ids(level)
    path = Rails.root.join(format(BASELINE_FIXTURE, level))
    raise MissingCatalog, "baseline fixture missing: #{path}" unless File.exist?(path)

    json = JSON.parse(File.read(path))
    Array(json.dig("profile", "imports")).flat_map do |import|
      Array(import["include-controls"]).flat_map { |inc| Array(inc["with-ids"]) }
    end.uniq
  end

  def catalog
    @catalog ||= ControlCatalog.find_by("name ILIKE ?", "%Rev 5%") ||
                 raise(MissingCatalog, "no Rev 5 control catalog — run db:seed first")
  end

  # ── One boundary, whole chain ────────────────────────────────────────────

  def build_boundary(role:, org_name:, boundary_name:, control_ids:, baseline:)
    org      = upsert_organization(org_name)
    boundary = upsert_boundary(boundary_name, org)
    profile  = build_profile(boundary_name, control_ids, baseline)
    ssp      = build_ssp(profile, boundary, boundary_name)
    sap      = build_sap(ssp, profile, boundary_name)
    sar      = build_sar(ssp, boundary_name)
    poams    = build_poams(sar, boundary, boundary_name)

    boundary.update!(profile_document_id: profile.id) if boundary.profile_document_id != profile.id

    { role: role, organization: org, boundary: boundary, profile: profile,
      ssp: ssp, sap: sap, sar: sar, poams: poams,
      evidence: build_evidence(boundary, boundary_name) }
  end

  def upsert_organization(name)
    Organization.find_or_create_by!(name: name) do |org|
      org.description = "Reference estate organization (#845). Not a real organization."
      org.status      = "active"
    end
  end

  def upsert_boundary(name, org)
    AuthorizationBoundary.find_or_create_by!(name: name) do |boundary|
      boundary.organization = org
      boundary.status       = "authorized"
      boundary.description  = "Reference estate authorization boundary (#845)."
      boundary.authorization_boundary_description =
        "Everything operated by #{org.name} within the reference estate."
    end
  end

  def build_profile(label, control_ids, baseline)
    profile = ProfileDocument.find_or_initialize_by(name: "#{label} — Profile")
    profile.control_catalog_id = catalog.id
    profile.baseline_level     = baseline
    profile.description        = "Reference estate profile (#845), #{@tier} tier."
    profile.save!

    ProfileControlSelectionService.new(profile).update(control_ids)

    # A published profile with a resolved catalog is what SspFromProfileService
    # requires; this mirrors db/seeds.rb `demo_published_profile`.
    resolved = OscalResolvedProfileCatalogService.new(profile).export
    profile.update!(resolved_catalog_json: JSON.parse(resolved),
                    lifecycle_status:      "published",
                    published:             PINNED_ASSESSMENT[:start].iso8601)
    profile
  end

  # SspFromProfileService does NOT set authorization_boundary_id, and an SSP
  # with a nil boundary is treated as instance-wide and shown to every signed-in
  # user (#952). The builder must set it.
  def build_ssp(profile, boundary, label)
    name = "#{label} — SSP"
    existing = SspDocument.find_by(name: name)
    return existing if existing

    ssp = SspFromProfileService.new(profile, name: name).create
    ssp.update!(authorization_boundary_id: boundary.id)
    ssp
  end

  def build_sap(ssp, profile, label)
    name = "#{label} — SAP"
    SapDocument.find_by(name: name) ||
      SapGeneratorService.new(name: name,
                              ssp_document:     ssp,
                              profile_document: profile,
                              assessment_type:  "initial",
                              assessment_start: PINNED_ASSESSMENT[:start],
                              assessment_end:   PINNED_ASSESSMENT[:end]).generate
  end

  # The pinned deadline is the point: left nil, PoamGeneratorService resolves
  # one from the remediation SLA as Time.current + N days, and every
  # regeneration of the committed OSCAL would differ.
  def build_sar(ssp, label)
    name = "#{label} — SAR"
    SarDocument.find_by(name: name) ||
      SarFromSspService.new(ssp, name: name, deadline: PINNED_DEADLINE).create
  end

  # Three POA&Ms with genuinely different postures, so screens that filter or
  # sort by status and deadline have something to show.
  def build_poams(sar, boundary, label)
    # `published` is the terminal state in Lifecycle::LIFECYCLE_STATUSES
    # (started → in_progress → published); there is no "completed".
    [
      { suffix: "Initial", lifecycle: "published",   deadline: Time.utc(2026, 6, 30) },
      { suffix: "Current", lifecycle: "in_progress", deadline: PINNED_DEADLINE },
      { suffix: "Overdue", lifecycle: "in_progress", deadline: Time.utc(2026, 2, 1) }
    ].map do |spec|
      name = "#{label} — POA&M (#{spec[:suffix]})"
      existing = PoamDocument.find_by(name: name)
      next existing if existing

      generated = PoamGeneratorService.new(name: name, sar_document: sar,
                                           authorization_boundary: boundary).generate
      document = generated.poam_document
      document.update!(lifecycle_status: spec[:lifecycle])
      document.poam_risks.update_all(deadline: spec[:deadline])
      document.poam_items.update_all(updated_at: Time.current)
      document
    end
  end

  # Types and statuses come from the Evidence enums, not invented strings —
  # an invalid enum raises at assignment rather than failing validation.
  EVIDENCE_KINDS = %w[policy_document test_result scan_result].freeze

  def build_evidence(boundary, label)
    EVIDENCE_KINDS.each_with_index.map do |kind, idx|
      title = "#{label} — #{kind.tr('_', ' ').titleize}"
      Evidence.find_by(title: title) || create_evidence(boundary, title, kind, idx)
    end
  end

  def create_evidence(boundary, title, kind, idx)
    evidence = Evidence.new(
      title:                  title,
      evidence_type:          kind,
      status:                 "reviewed",
      description:            "Reference estate evidence (#845) of type #{kind}.",
      source:                 "reference-estate",
      authorization_boundary: boundary
    )
    evidence.collected_at = PINNED_ASSESSMENT[:start] + idx.days
    evidence.save!
    evidence.stamp_collection!(actor: @actor, label: "Reference Estate") if @actor
    evidence
  end

  # ── The leveraging relationship ──────────────────────────────────────────

  # Boundary 1 declares what it provides to its customers and what it hands
  # back. These tags are the one thing generation must never invent (#955) —
  # they are a system owner authoring a customer responsibility matrix, which
  # is precisely what the reference estate is deliberately doing here.
  def declare_customer_responsibility_split(leveraged)
    statements = SspControlStatement
                   .joins(:ssp_control)
                   .where(ssp_controls: { ssp_document_id: leveraged[:ssp].id })
                   .includes(:ssp_control)

    statements.each do |statement|
      control_id = statement.ssp_control.control_id

      if PROVIDED_CONTROL_IDS.include?(control_id)
        statement.update!(
          set_parameters_data:  [ { "tag" => "provided" } ],
          implementation_prose: "#{control_id.upcase} is implemented centrally by the reference " \
                                "platform and inherited by every leveraging system."
        )
      elsif RESPONSIBILITY_CONTROL_IDS.include?(control_id)
        statement.update!(
          set_parameters_data:  [ { "tag" => "responsibility" } ],
          implementation_prose: "The reference platform does not implement #{control_id.upcase}. " \
                                "Each leveraging system must address it for its own environment."
        )
      end
    end
  end

  def wire_leveraging(leveraged:, leveraging:)
    authorization = LeveragedAuthorization.find_or_create_by!(
      leveraging_boundary: leveraging[:boundary],
      leveraged_boundary:  leveraged[:boundary]
    ) do |la|
      la.name            = "#{leveraging[:boundary].name} leverages #{leveraged[:boundary].name}"
      la.crm_type        = "oscal_with_access"
      la.date_authorized = PINNED_ASSESSMENT[:start].to_date
      la.description     = "Reference estate leveraged authorization (#845), scenario 1."
    end

    LeveragedAuthorizationService.populate_from_leveraged!(authorization)

    # Deliberately NOT the populate return value. That counts links *created
    # this run* — `links += 1 if link.changed? && link.save` — so a second
    # build reports 0 even though the estate is fully wired. (Its doc comment
    # claims "or found, for idempotency"; the code does not do that.) A
    # builder that reported 0 links on a correct re-run would look broken.
    inheritance_link_count(leveraging[:ssp])
  end

  def inheritance_link_count(ssp)
    SspControlStatementInheritance
      .joins(:ssp_control_statement)
      .where(ssp_control_statements: { ssp_control_id: ssp.ssp_controls.select(:id) })
      .count
  end
end
