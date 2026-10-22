# frozen_string_literal: true

# ProfileSelection — which controls one OSCAL profile `import` selects from its
# catalog (#1252). The one definition: the profile parser stores what this
# returns, the import resolver records it per import, and the resolved catalog
# is built from the stored rows, so the three cannot disagree.
#
# Per the OSCAL profile resolution specification:
#
#   include-all                    every control in the catalog, at every depth
#   include-controls / with-ids    the named controls
#   include-controls / matching    controls whose id matches the glob pattern
#                                  (`*` any run of characters, `?` one character)
#   with-child-controls="yes"      also every descendant control of each match
#   exclude-controls               the same selectors, removed after inclusion
#
# It previously honoured `with-ids` alone. A profile that includes the whole
# catalog selected nothing, excluded controls stayed selected, and enhancements
# meant to come in with their parent did not.
#
# Order: an import's selectors are read in document order. `with-ids` keeps the
# order the profile lists them (NIST's baselines list them in catalog order, so
# their selection is unchanged); `include-all` and `matching` follow catalog
# order. A control selected twice keeps its first position.
#
# `controls` is the catalog's OSCAL control tree in catalog order: one
# `[id, parent_id]` pair per control, parent_id nil at the top level. Statement
# items are not controls and must not be in it.
#
# NIST 800-53: CM-2 (the baseline configuration is the one the profile states),
# PL-10 (baseline selection), PL-11 (baseline tailoring).
class ProfileSelection
  YES = "yes"

  def initialize(controls)
    @order    = controls.map { |id, _| id.to_s }
    @known    = @order.to_set
    @children = Hash.new { |h, k| h[k] = [] }
    controls.each { |id, parent| @children[parent.to_s] << id.to_s if parent.present? }
  end

  # @param import [Hash] one entry of a profile's `imports` (OSCAL JSON model)
  # @return [Array<String>] the selected control ids, in selection order
  def select(import)
    included = []
    included.concat(@order) if import.key?("include-all")
    Array(import["include-controls"]).each { |selector| included.concat(matches(selector)) }

    excluded = Array(import["exclude-controls"]).flat_map { |selector| matches(selector) }.to_set
    included.uniq.reject { |id| excluded.include?(id) }
  end

  # The ids a `with-ids` selector names that are not controls in this catalog,
  # so the caller can report them rather than drop them silently.
  def unknown_ids(import)
    (Array(import["include-controls"]) + Array(import["exclude-controls"]))
      .flat_map { |selector| Array(selector["with-ids"]) }
      .map(&:to_s).uniq.reject { |id| @known.include?(id) }
  end

  private

  def matches(selector)
    # A named id the catalog lacks is kept, as it always was, and reported by
    # #unknown_ids: dropping it here would hide the profile's error.
    hits = Array(selector["with-ids"]).map(&:to_s)
    Array(selector["matching"]).each do |m|
      pattern = glob(m["pattern"])
      hits.concat(@order.select { |id| pattern.match?(id) }) if pattern
    end
    hits = hits.flat_map { |id| [ id ] + descendants(id) } if selector["with-child-controls"] == YES
    hits.uniq
  end

  def descendants(id)
    @children[id].flat_map { |child| [ child ] + descendants(child) }
  end

  # OSCAL's `matching` pattern is a glob over the whole id.
  def glob(pattern)
    return nil if pattern.blank?

    body = pattern.to_s.chars.map { |c| { "*" => ".*", "?" => "." }[c] || Regexp.escape(c) }.join
    Regexp.new("\\A#{body}\\z")
  end
end
