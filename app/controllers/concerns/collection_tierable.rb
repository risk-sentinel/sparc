# frozen_string_literal: true

# #948 — one way for an index action to tier its collection, so five screens
# cannot each wire it slightly differently.
#
# ── The rule this concern exists to hold ───────────────────────────────────
#
# `build_tiering` takes the relation the caller has ALREADY scoped and filtered.
# It never calls `boundary_scoped_relation` itself, never touches
# `current_user`, and never adds a `where`. Generalising the TIERING must not
# generalise VISIBILITY — that is the acceptance criterion of #948 and the #908
# rule it inherits. Every screen keeps `boundary_scoped_relation` exactly as it
# is, and a spec per screen asserts the visible set is identical before and
# after.
#
# ── The instance tier means different things per model ─────────────────────
#
# `BoundaryScopedDocument` carries `global_fallback:`, and it is the difference
# between "deliberately shared with everyone" and "a legacy orphan nobody has
# repaired yet". A single shared label would tell a user the second thing is the
# first, so each screen supplies its own wording and this concern picks the
# default from the flag the model already declares.
module CollectionTierable
  extend ActiveSupport::Concern

  # Evidence: a nil boundary is genuinely instance-wide. On the owner's reading
  # this is PROVIDER material arriving from a leveraged SSP as inherited or
  # common controls, which is why it has its own authority chain for attesting
  # (#947) and its own tier here.
  GLOBAL_TIER_LABEL = "Instance-wide"
  GLOBAL_TIER_HELP  = "Not owned by one system — inherited or common-control material, " \
                      "visible to every signed-in user."

  # SSP / SAP / SAR / POA&M: per-system by definition, so a nil boundary is an
  # unrepaired row, NOT a sharing decision. #952 already stopped showing these
  # to everyone; the wording here has to match that reality.
  ORPHAN_TIER_LABEL = "Not assigned to a system"
  ORPHAN_TIER_HELP  = "These predate the rule that every document names its system. " \
                      "They are visible to Instance-Admins only — attach each one from " \
                      "the boundary's Artifact Summary."

  private

  # `scope`   — already boundary-scoped AND already filtered.
  # `records` — the page being rendered.
  def build_tiering(scope:, records:)
    CollectionTiering.new(
      scope: scope,
      records: records,
      instance_label: instance_tier_label,
      instance_help: instance_tier_help
    )
  end

  # Read from the model's own declaration rather than repeated per controller,
  # so the two readings cannot drift from the flag that actually governs them.
  def instance_tier_label
    global_boundary_fallback? ? GLOBAL_TIER_LABEL : ORPHAN_TIER_LABEL
  end

  def instance_tier_help
    global_boundary_fallback? ? GLOBAL_TIER_HELP : ORPHAN_TIER_HELP
  end

  def global_boundary_fallback?
    return true unless respond_to?(:bsd_global_fallback, true)

    bsd_global_fallback
  end
end
