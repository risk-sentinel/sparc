# frozen_string_literal: true

# #984 — deterministic fixtures for the four collection screens that hold
# nothing on a demo-seeded instance.
#
# `tests/ui-smoke/test_collection_views.py` runs three checks — card view, list
# view, and view-mode persistence — across 16 screens. On `review_queue`,
# `promotion_queue`, `leveraged_poams` and `federation_peers` all three SKIPPED,
# because the screen has no records to draw. 4 screens x 3 checks = 12 skips.
#
# `authoritative_sources` is seeded here too. It was NOT among the four the
# issue measured — the instance it was measured on had curated rows — but a
# freshly seeded database has none, so it would skip there for exactly the same
# reason. Seeding it now rather than rediscovering it on the next fresh install.
#
# The guard was honest about it: you cannot assert "?view=card drew cards and no
# table" on a screen with nothing to draw, so it skipped rather than passing
# vacuously. Page load and console errors were still asserted. What never ran is
# the card-versus-table assertion — the file's actual subject, and exactly what
# a change to the #888 shared component would break on all sixteen at once.
#
# ── Why the seed and not the test ─────────────────────────────────────────
#
# These are index screens, and view-mode persistence is a property of a VISIT:
# the toggle writes a cookie and the next request has to honour it. A fixture
# created and torn down inside one test cannot exercise that. They also have to
# exist before the browser arrives, which a per-test factory cannot guarantee
# for a suite that talks to a running deployment over HTTP.
#
# ── Why here and not ReferenceEstateBuilder ───────────────────────────────
#
# The estate already builds review and promotion entries, but it lives behind
# `SPARC_SEED_REFERENCE` — a SEPARATE opt-in from `SPARC_SEED_DEMO`. #984 asks
# for zero skips on a demo-seeded instance, so the fixtures belong on the demo
# path. The estate is unchanged and still builds its own.
#
# Everything here is idempotent: re-running the seed finds what it made.

puts "\nSeeding #984 collection-screen fixtures..."

actor         = User.find_by(admin: true)
auth_boundary = AuthorizationBoundary.find_by(name: "Cloud Web Application ATO") ||
                AuthorizationBoundary.order(:id).first
default_org   = auth_boundary&.organization || Organization.order(:id).first

# ──────────────────────────────────────────────────────────────────────────
# 1. review_queue — a profile awaiting sign-off
# ──────────────────────────────────────────────────────────────────────────
#
# ReviewQueueController accepts ControlCatalog, ProfileDocument and CdefDocument
# only, so the entry has to be one of those. It is a SEPARATE profile rather
# than flipping a seeded baseline: the demo baselines are published, and a
# published profile sitting at `pending_review` is a contradiction the screen
# would render as nonsense. A proposed revision awaiting review is what actually
# happens.
#
# NOTE the second gate. The screen filters per-user through
# `DocumentApprovalService#can_approve?`, so a row in `pending_review` is not
# enough on its own — it has to be approvable by whoever is looking. An Instance
# Admin always can (and the ui-smoke SA token is one), so the fixture is visible
# to the gate that matters without inventing a roster.
source_profile = ProfileDocument.where(lifecycle_status: "published")
                                .where.not(resolved_catalog_json: nil)
                                .order(:id).first
catalog = source_profile&.control_catalog || ControlCatalog.order(:id).first

if catalog.nil?
  puts "  Skipped review-queue fixture — no control catalog is loaded."
else
  revision_name = "Cloud Web Application ATO — Profile (proposed revision)"
  revision = ProfileDocument.find_or_initialize_by(name: revision_name)

  if revision.new_record?
    revision.control_catalog  = catalog
    revision.baseline_level   = source_profile&.baseline_level || "moderate"
    revision.description      = "DEMO/SAMPLE — a proposed revision awaiting review, so the " \
                                "review queue is not empty on a demo instance (#984)."
    revision.lifecycle_status = "in_progress"
    revision.save!

    if source_profile
      control_ids = source_profile.profile_controls.pluck(:control_id).compact.sort.first(25)
      ProfileControlSelectionService.new(revision).update(control_ids) if control_ids.any?
    end
  end

  # Re-applied even on an existing row: a previous run of the demo seed may have
  # created it, and someone may since have approved it in the UI. The queue is
  # what this fixture exists to populate.
  unless revision.approval_status == "pending_review"
    revision.update!(approval_status:   "pending_review",
                     submitted_by_user: actor,
                     submitted_at:      Time.current,
                     lifecycle_status:  "in_progress")
  end
  puts "  Review queue: #{revision.name.inspect} (#{revision.approval_status})"
end

# ──────────────────────────────────────────────────────────────────────────
# 2. promotion_queue — a back-matter resource proposed for promotion
# ──────────────────────────────────────────────────────────────────────────
#
# Promotes an EXISTING resource where one is available — `EvidenceControlLink`
# syncs one per evidence linked to a document — rather than inventing a resource
# nothing points at. `.order(:uuid)` because "whichever row comes back first" is
# not a fixture, it is a coin flip that would move the promotion between seeds.
#
# The already-pending check is what makes this idempotent. Without it the seed
# promotes the first NOT-yet-pending resource every run, so each re-seed adds
# another to the queue — a fixture that grows every time it is applied is a slow
# leak, not a fixture.
already_pending = BackMatterResource.pending_promotion.exists?
promotable = unless already_pending
  # "none" only — the column is NOT NULL with default "none", so a nil branch
  # would be dead code, and "approved"/"rejected" rows are settled, not
  # candidates.
  BackMatterResource.where(promotion_status: "none")
                    .where(archived_at: nil)
                    .order(:uuid).first
end

if already_pending
  puts "  Promotion queue: already populated (#{BackMatterResource.pending_promotion.count} pending)"
elsif promotable
  promotable.update!(promotion_status: "pending_review")
  puts "  Promotion queue: #{promotable.title.inspect}"
else
  # No evidence-derived resource on this instance — stand one up so the screen
  # still renders. Marked DEMO/SAMPLE like every other fabricated fixture.
  standalone = BackMatterResource.find_or_initialize_by(
    title: "DEMO/SAMPLE — Shared Encryption Policy"
  )
  if standalone.new_record?
    standalone.uuid             = SecureRandom.uuid
    standalone.description      = "DEMO/SAMPLE — proposed for promotion so the promotion " \
                                  "queue is not empty on a demo instance (#984)."
    standalone.href             = "https://example.gov/policies/encryption.pdf"
    standalone.source           = "managed"
    standalone.organization     = default_org
    standalone.promotion_status = "pending_review"
    standalone.save!
  elsif standalone.promotion_status != "pending_review"
    standalone.update!(promotion_status: "pending_review")
  end
  puts "  Promotion queue: #{standalone.title.inspect} (standalone)"
end

# ──────────────────────────────────────────────────────────────────────────
# 3. leveraged_poams — a POA&M owned by a leveraged system
# ──────────────────────────────────────────────────────────────────────────
#
# `LeveragedPoamDocumentsController` lists POA&Ms owned by boundaries the user's
# boundaries LEVERAGE, so a POA&M row alone renders nothing: the leveraging
# relationship is what makes it visible. The demo seed had neither — no
# `LeveragedAuthorization` exists on a demo instance at all.
if auth_boundary.nil?
  puts "  Skipped leveraged-POA&M fixture — no authorization boundary seeded."
else
  leveraged_boundary = AuthorizationBoundary.find_or_create_by!(
    name: "Shared Platform Services (leveraged)"
  ) do |b|
    b.description = "DEMO/SAMPLE — a leveraged provider platform, so the leveraging " \
                    "system's POA&M inheritance has something to show (#984)."
    b.status      = "active"
  end
  leveraged_boundary.update!(organization: default_org) if leveraged_boundary.organization_id.nil?

  # `date_authorized` is NOT optional even though the column is nullable: OSCAL
  # requires it on every `leveraged-authorization`, and
  # `OscalSspExportService#build_leveraged_authorizations` emits the entry
  # regardless. Omitting it made EVERY SSP on the leveraging boundary fail
  # export validation with
  #   /system-implementation/leveraged-authorizations/0: missing required
  #   properties: date-authorized
  # — so a fixture added to un-skip four collection screens broke SSP export
  # (JSON, XML and YAML) for the whole demo estate. Caught by the ui-smoke gate,
  # invisible to rspec. `ReferenceEstateBuilder#wire_leveraging` sets both these
  # fields for the same reason; this matches it.
  leveraged_authorization = LeveragedAuthorization.find_or_create_by!(
    leveraging_boundary: auth_boundary,
    leveraged_boundary:  leveraged_boundary
  ) do |la|
    la.name            = "#{auth_boundary.name} leverages #{leveraged_boundary.name}"
    la.crm_type        = "oscal_with_access"
    la.date_authorized = Date.new(2026, 1, 15)
    la.description     = "DEMO/SAMPLE — leveraged authorization (#984)."
  end

  # Heal a row created before the line above set the date — otherwise a demo
  # instance seeded once already keeps exporting invalid SSPs forever.
  if leveraged_authorization.date_authorized.blank?
    leveraged_authorization.update!(date_authorized: Date.new(2026, 1, 15))
  end

  leveraged_poam = PoamDocument.find_or_create_by!(
    name: "Shared Platform Services — Plan of Action & Milestones"
  ) do |d|
    d.file_type              = "json"
    d.status                 = "completed"
    d.lifecycle_status       = "in_progress"
    d.poam_version           = "1.0"
    d.oscal_version          = "1.1.2"
    d.system_id              = "shared-platform-services"
    d.description            = "DEMO/SAMPLE — the leveraged platform's open items, visible " \
                               "to the leveraging system's AO (#984)."
    d.authorization_boundary = leveraged_boundary
  end
  puts "  Leveraged POA&Ms: #{leveraged_poam.name.inspect} on #{leveraged_boundary.name.inspect}"
end

# ──────────────────────────────────────────────────────────────────────────
# 4. authoritative_sources — instance-curated reference material
# ──────────────────────────────────────────────────────────────────────────
#
# `source: "authoritative"` is the instance/policy-curated tier, which the
# screen filters on. `globally_available` so the screen is not empty for a
# non-admin either: `visible_resources` shows a non-admin only globally
# available rows plus their own organization's, and a fixture that renders for
# exactly one identity is half a fixture.
#
# Safe to leave unreferenced. #959 scoped `BackMatterBuilder#authoritative_resources`
# to the UUIDs a document actually points at, so these do NOT get embedded into
# every export the way instance-wide back matter used to. Labelled DEMO/SAMPLE
# for the same reason that mattered: unlabelled smoke residue reached a public
# wiki screenshot once.
[
  {
    title: "DEMO/SAMPLE — NIST SP 800-53 Rev 5 (source publication)",
    href:  "https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final",
    description: "DEMO/SAMPLE — the control catalog this instance's baselines derive from.",
    media_type: "text/html"
  },
  {
    title: "DEMO/SAMPLE — Organization Information Security Policy",
    href:  "https://example.gov/policies/information-security-policy.pdf",
    description: "DEMO/SAMPLE — instance-curated policy referenced by control implementations.",
    media_type: "application/pdf"
  }
].each do |spec|
  resource = BackMatterResource.find_or_initialize_by(title: spec[:title])
  next unless resource.new_record?

  resource.uuid                = SecureRandom.uuid
  resource.href                = spec[:href]
  resource.description         = spec[:description]
  resource.media_type          = spec[:media_type]
  resource.source              = "authoritative"
  resource.rel                 = "reference"
  resource.globally_available  = true
  resource.organization        = default_org
  resource.save!
end
puts "  Authoritative sources: #{BackMatterResource.authoritative.count} curated reference(s)"

# ──────────────────────────────────────────────────────────────────────────
# 5. federation_peers — one peer, disabled
# ──────────────────────────────────────────────────────────────────────────
#
# Deliberately DISABLED. An enabled peer is a standing outbound-sync target, and
# a demo seed has no business creating one that points at a host it does not
# own; disabled still renders a row, which is all the screen needs.
peer = FederationPeer.find_or_create_by!(name: "DEMO/SAMPLE — Partner Agency SPARC") do |p|
  p.base_url = "https://sparc.partner-agency.example.gov"
  p.enabled  = false
end
puts "  Federation peers: #{peer.name.inspect} (enabled=#{peer.enabled})"

puts "Done! #984 collection-screen fixtures seeded."
