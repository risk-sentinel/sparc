# frozen_string_literal: true

# #1100 — the demo SSPs carry the statement structure their catalog defines.
#
# The demo SSPs are imported from committed OSCAL (#946), and that OSCAL holds
# ONE implementation statement per control. NIST divides a control into as many
# as nine addressable parts, and the per-statement editor has nothing to edit
# without them.
#
# Instances that existed before #1100 got the parts from a one-time migration,
# `BackfillSspStatementSubParts`. A FRESH install never runs that migration: the
# database is built from `schema.rb`, and even if it did run, there would be no
# SSP for it to find yet. So a freshly seeded demo instance had 149 statements
# for 150 controls and zero controls with more than one — and the six
# statement-authoring checks in the UI smoke suite skipped on exactly the
# instance the release gate builds.
#
# This applies the same additive backfill to the demo SSPs, after they exist.
#
# ── Why its own section and not inside `demo_ssp_sar` ──────────────────────
#
# `demo_ssp_sar` destroys and re-imports its SSPs whenever it re-runs. Bumping
# it to carry this would rebuild the demo estate on every existing instance to
# add rows that an additive pass can add in place. This section's version
# includes `demo_ssp_sar`'s instead (see db/seeds.rb), so it follows any
# re-import without causing one.
#
# ── Additive, and safe to repeat ───────────────────────────────────────────
#
# `backfill_ssp_statements!` adds the MISSING statements and leaves existing
# rows alone, so prose someone wrote against a statement survives. A document
# that already has the structure is skipped rather than passed through again:
# the service flags a document "needs re-association" when it finds nothing to
# add, which is the right answer for a document whose catalog cannot be
# resolved and the wrong one for a document that is simply complete.

puts "\nSeeding #1100 statement sub-parts for the demo SSPs..."

[
  "ACME Cloud Platform — SSP (NIST SP 800-53 Rev 5, Moderate)",
  "ACME HR Portal — SSP (NIST SP 800-53 Rev 5, Low)"
].each do |name|
  SspDocument.where(name: name).find_each do |ssp|
    structured = SspControlStatement
                   .where(ssp_control_id: ssp.ssp_controls.select(:id))
                   .group(:ssp_control_id)
                   .having("COUNT(*) > 1")
                   .limit(1)
                   .pluck(:ssp_control_id)
                   .any?

    if structured
      puts "  '#{ssp.name}': already has sub-part statements — left as is."
      next
    end

    added = CatalogPartExtractorService.new(ssp).backfill_ssp_statements!
    puts "  '#{ssp.name}': +#{added} statement(s) from the catalog's parts."
  end
end
