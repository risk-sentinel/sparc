# frozen_string_literal: true

# The one reader for a resolved-profile catalog document (#999).
#
# ── Why this exists ────────────────────────────────────────────────────────
#
# `profile_documents.resolved_catalog_json` is written by three paths — this
# app's own resolver, `ProfileJsonParserService` when an already-resolved
# profile is IMPORTED, and the seeds — and it was read by six services that
# each walked it privately:
#
#   SspFromProfileService  SarFromProfileService  CdefFromProfileService
#   CdefBaselineGapService CdefBulkApplyService   BaselineParameterService
#
# Every one of them walked `groups[].controls[]` and stopped there. In a
# conformant OSCAL catalog an enhancement is NESTED inside its parent control
# (`ac-2` contains `ac-2.1` … `ac-2.11`), so those six saw base controls only.
# Import NIST's published HIGH resolved catalog and generate an SSP from it and
# you got **188 controls instead of 370** — every enhancement dropped, no error,
# no warning. Measured against the seeded Rev 5 source catalog: 324 top-level
# controls and 872 nested.
#
# So this class is not a refactor for tidiness. It is the fix: one traversal
# that reads BOTH shapes, so a document is understood the same way whoever
# wrote it and whichever era of SPARC produced it.
#
# ── What it accepts ────────────────────────────────────────────────────────
#
# Wrapped (`{"catalog" => {...}}`) or bare, nested or flat, string- or
# symbol-keyed at the root. Nested groups are walked too — OSCAL permits them
# and NIST's own catalog uses one level, but nothing should depend on that.
#
#   ResolvedCatalog.wrap(profile.resolved_catalog_json).each_control do |control, group|
#     …
#   end
#
# Controls arrive in document order, parent before its enhancements, which is
# the order the generators relied on when they were building `row_order`.
class ResolvedCatalog
  def self.wrap(document)
    document.is_a?(self) ? document : new(document)
  end

  def initialize(document)
    @catalog = extract_catalog(document)
  end

  def groups
    Array(@catalog["groups"])
  end

  def metadata
    @catalog["metadata"] || {}
  end

  def back_matter
    @catalog["back-matter"] || {}
  end

  def any? = groups.any?

  # Yields every control in the document, nested or not, with the GROUP it
  # belongs to. An enhancement is yielded with its parent's group, because a
  # nested control has no group of its own and callers use the group for the
  # control family.
  def each_control(&block)
    return enum_for(:each_control) unless block_given?

    groups.each { |group| walk_group(group, group, &block) }
    self
  end

  def controls
    each_control.map { |control, _group| control }
  end

  def control_ids
    controls.filter_map { |control| control["id"] }
  end

  def find(control_id)
    wanted = control_id.to_s.downcase
    each_control { |control, _group| return control if control["id"].to_s.downcase == wanted }
    nil
  end

  private

  def extract_catalog(document)
    hash = document.respond_to?(:to_unsafe_h) ? document.to_unsafe_h : document
    return {} unless hash.is_a?(Hash)

    hash = hash.transform_keys(&:to_s)
    inner = hash["catalog"]
    inner.is_a?(Hash) ? inner.transform_keys(&:to_s) : hash
  end

  # `group` is threaded down rather than re-derived, so an enhancement three
  # levels deep still reports the family it lives in.
  def walk_group(node, group, &block)
    Array(node["controls"]).each { |control| walk_control(control, group, &block) }
    Array(node["groups"]).each { |child| walk_group(child, child, &block) }
  end

  def walk_control(control, group, &block)
    return unless control.is_a?(Hash)

    block.call(control, group)
    Array(control["controls"]).each { |child| walk_control(child, group, &block) }
  end
end
