# frozen_string_literal: true

# #948 — group a collection screen Instance → Organization → Boundary, so
# evidence (and every other collection) is read in the structure the rest of the
# product already uses: `AuthorizationBoundary belongs_to :organization`, and the
# #796 sidebar is already Organizations → Authorization Boundaries.
#
# ── It never decides who may see what ──────────────────────────────────────
#
# This receives an ALREADY-SCOPED relation and groups it. It does not filter, it
# does not consult `current_user`, and it has no access to one. That is the #908
# rule unchanged (`CollectionBrowseQuery` receives an already-scoped relation),
# and it is the whole reason tiering can be generalised across six screens
# safely: generalising the TIERING does not generalise VISIBILITY. The
# enforcing check is a spec per screen asserting the visible set is identical
# before and after.
#
# ── "Instance" means different things on different screens ─────────────────
#
# A nil boundary is NOT one condition. `BoundaryScopedDocument` takes a
# `global_fallback:` flag per model:
#
#   * Evidence (`global_fallback: true`) — a boundary-less row is genuinely
#     instance-wide and visible to every signed-in user. On the owner's reading
#     it is PROVIDER material, arriving from a leveraged SSP as inherited or
#     common controls. That deserves its own labelled tier.
#   * SSP / SAP / SAR / POA&M (`global_fallback: false`, #952) — a boundary-less
#     row is a legacy ORPHAN, not instance-wide, and is visible to
#     Instance-Admins only. Labelling it "Instance" would tell a user an
#     unrepaired orphan is deliberately shared estate-wide.
#
# So the caller supplies the label and the help text, and the two readings never
# get collapsed into one word.
#
# ── A boundary with no organization ────────────────────────────────────────
#
# `belongs_to :organization, optional: true`, so the middle tier can be missing.
# The issue's three tiers do not cover it. Such boundaries get their own group
# rather than being folded into the instance tier, which would say something
# false: the records DO belong to a system, that system just is not filed under
# an organization yet.
#
# ── Counts are of the FILTERED SET, records are the PAGE ───────────────────
#
# A tier header answers "how much do I have here", which is a property of the
# whole filtered collection, not of the page a user happens to be on. So counts
# come from the scope and records come from the page: a tier can read 24 and
# show 8 beneath it. Per-page counts would be arithmetically honest and useless
# for reading the estate.
# NIST 800-53 Controls:
#   AC-3 Access Enforcement — this class deliberately enforces NOTHING. It
#        receives an already-scoped relation and groups it, has no access to
#        `current_user`, and adds no `where`. Generalising the tiering across
#        six screens must not generalise visibility; the per-screen
#        "visible set is identical" specs are what hold that line.
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class CollectionTiering
  # One boundary's worth of records within an organization group.
  BoundaryTier = Struct.new(:boundary, :label, :count, :records, keyword_init: true) do
    def dom_id = "tier-boundary-#{boundary&.id || 'none'}"
  end

  # An organization, the instance tier, or the unaffiliated-boundaries group.
  OrganizationTier = Struct.new(:key, :organization, :label, :help, :count, :boundaries,
                                keyword_init: true) do
    def dom_id = "tier-org-#{key}"
    def instance? = key == "instance"
  end

  # `scope`   — the already-scoped, already-filtered relation (counts).
  # `records` — the current page of that relation (what renders).
  def initialize(scope:, records:, instance_label:, instance_help: nil)
    @scope          = scope
    @records        = records
    @instance_label = instance_label
    @instance_help  = instance_help
  end

  # Tier only when there is more than one boundary to tell apart.
  #
  # Owner decision: automatic, not a view mode and not a default-with-opt-out. A
  # single-boundary user is not made worse off because they never see a tree
  # with one branch. `nil` counts as a distinct group, so evidence split between
  # one boundary and the instance tier still tiers — that split is exactly what
  # a user needs to see.
  def tiered?
    @tiered = distinct_boundary_ids.length > 1 if @tiered.nil?
    @tiered
  end

  # [OrganizationTier], instance first, then organizations by name, then
  # unaffiliated boundaries. Empty when there is nothing to show.
  def tiers
    @tiers ||= build_tiers
  end

  private

  def distinct_boundary_ids
    @distinct_boundary_ids ||= @scope.reorder(nil).distinct.pluck(:authorization_boundary_id)
  end

  # id => count, over the FILTERED scope (not the page).
  def counts_by_boundary
    @counts_by_boundary ||= @scope.reorder(nil).group(:authorization_boundary_id).count
  end

  def records_by_boundary
    @records_by_boundary ||= @records.group_by(&:authorization_boundary_id)
  end

  def boundaries_by_id
    @boundaries_by_id ||= AuthorizationBoundary.where(id: distinct_boundary_ids.compact)
                                               .includes(:organization)
                                               .index_by(&:id)
  end

  def build_tiers
    groups = []
    groups << instance_tier if distinct_boundary_ids.include?(nil)
    groups.concat(organization_tiers)
    groups.compact
  end

  def instance_tier
    OrganizationTier.new(
      key: "instance",
      organization: nil,
      label: @instance_label,
      help: @instance_help,
      count: counts_by_boundary[nil].to_i,
      boundaries: [
        BoundaryTier.new(boundary: nil, label: @instance_label,
                         count: counts_by_boundary[nil].to_i,
                         records: records_by_boundary[nil] || [])
      ]
    )
  end

  def organization_tiers
    grouped = boundaries_by_id.values.group_by(&:organization)

    named, unaffiliated = grouped.partition { |organization, _| organization.present? }

    tiers = named.sort_by { |organization, _| organization.name.to_s.downcase }
                 .map { |organization, boundaries| organization_tier(organization, boundaries) }

    unaffiliated.each do |_, boundaries|
      tiers << OrganizationTier.new(
        key: "unaffiliated",
        organization: nil,
        label: "Boundaries with no organization",
        help: "These systems are not filed under an organization. They are visible exactly as " \
              "before — assign an organization to file them in the hierarchy.",
        count: boundaries.sum { |b| counts_by_boundary[b.id].to_i },
        boundaries: boundary_tiers(boundaries)
      )
    end

    tiers
  end

  def organization_tier(organization, boundaries)
    OrganizationTier.new(
      key: organization.id.to_s,
      organization: organization,
      label: organization.name,
      help: nil,
      count: boundaries.sum { |b| counts_by_boundary[b.id].to_i },
      boundaries: boundary_tiers(boundaries)
    )
  end

  def boundary_tiers(boundaries)
    boundaries.sort_by { |b| b.name.to_s.downcase }.map do |boundary|
      BoundaryTier.new(
        boundary: boundary,
        label: boundary.name,
        count: counts_by_boundary[boundary.id].to_i,
        records: records_by_boundary[boundary.id] || []
      )
    end
  end
end
