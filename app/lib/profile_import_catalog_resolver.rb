# frozen_string_literal: true

# #1234 — which loaded catalog each of a profile's `imports` names.
#
# A profile may import several catalogs: NIST SP 800-53 plus an
# organization's own controls is the standard OSCAL way to build one baseline,
# because a profile can change a control but cannot add one. SPARC used to
# read `imports.first` only, so every other import's controls were titled from
# the wrong catalog (or not at all) and exported as though NIST published them.
#
# Each import resolves on its own, by the first of these that matches
# (owner, 2026-10-21):
#
#   1. a catalog UUID: the href (`#<uuid>` or `uuid:<uuid>`) or one of its
#      back-matter resource's rlinks names a loaded catalog's OSCAL uuid;
#   2. the NIST pattern: an rlink (or the href itself) names SP 800-53 and a
#      revision a loaded catalog's name also carries (the pre-#1234 rule).
#      Several catalogs can fit — an agency overlay named "... SP 800-53
#      Rev 5" fits as well as NIST's — so the fits are ranked: the catalog the
#      profile was uploaded against first, then the one holding the most of the
#      controls the import names. Taking the lowest id linked a NIST profile to
#      an overlay holding none of its controls, and every control was reported
#      as missing from its catalog;
#   3. the back-matter resource's title equals a loaded catalog's name, and
#      EXACTLY ONE catalog has that name. Two catalogs with one name is not a
#      match: guessing would attribute controls to the wrong source.
#
# An import nothing matches stays unlinked and is reported as a warning.
class ProfileImportCatalogResolver
  CATALOG_800_53 = "800-53"
  REV_PATTERN    = /rev\.?\s*(\d+)/i
  REVISION_WORD  = /revision[_\s]*(\d+)/i
  UUID_PATTERN   = /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/

  # #1252 — `unresolved` names the selectors an import uses that need its
  # catalog (include-all, matching, with-child-controls) when no loaded catalog
  # matched it; `unknown_ids` the `with-ids` its catalog does not hold.
  Resolution = Struct.new(:index, :href, :control_ids, :catalog, :matched_by, :label,
                          :unresolved, :unknown_ids, keyword_init: true) do
    def linked? = catalog.present?
  end


  # @param back_matter [Array<Hash>] the profile's raw `back-matter.resources`
  # @param preferred [ControlCatalog, nil] the catalog the profile was
  #   uploaded against, which wins among catalogs the NIST pattern fits
  def initialize(back_matter, catalogs: ControlCatalog.all.to_a, preferred: nil)
    @resources = Array(back_matter).index_by { |r| r["uuid"].to_s }
    @catalogs  = catalogs.sort_by(&:id)
    @preferred = preferred
  end

  # @param imports [Array<Hash>] the profile's raw `imports`
  # @return [Array<Resolution>] one per import, in document order
  def resolve(imports)
    Array(imports).each_with_index.map do |imp, index|
      href = imp["href"].to_s
      resource = @resources[href.delete_prefix("#")]
      catalog, matched_by = match(href, resource, imp)
      ids, unresolved, unknown = selection(imp, catalog)
      Resolution.new(index: index, href: href, control_ids: ids, catalog: catalog,
                     matched_by: matched_by, label: resource&.dig("title").presence || href,
                     unresolved: unresolved, unknown_ids: unknown)
    end
  end

  private

  # #1252 — a linked import is selected by ProfileSelection against its own
  # catalog's control tree. An unlinked one has no tree: its named ids are
  # kept, as before, less any it excludes by name, and every selector that
  # needs the catalog is reported instead of guessed (owner, 2026-10-22).
  def selection(imp, catalog)
    if catalog
      selector = ProfileSelection.new(tree_for(catalog))
      return [ selector.select(imp), [], selector.unknown_ids(imp) ]
    end

    named    = Array(imp["include-controls"]).flat_map { |ic| Array(ic["with-ids"]) }.map(&:to_s)
    excluded = Array(imp["exclude-controls"]).flat_map { |ic| Array(ic["with-ids"]) }.map(&:to_s)
    [ (named - excluded).uniq, catalog_selectors(imp), [] ]
  end

  def catalog_selectors(imp)
    selectors = Array(imp["include-controls"]) + Array(imp["exclude-controls"])
    used = []
    used << "include-all" if imp.key?("include-all")
    used << "matching" if selectors.any? { |s| Array(s["matching"]).any? }
    used << "with-child-controls" if selectors.any? { |s| s["with-child-controls"] == ProfileSelection::YES }
    used
  end

  def tree_for(catalog)
    (@trees ||= {})[catalog.id] ||= CatalogControlTree.for(catalog)
  end

  def match(href, resource, imp)
    rlinks = Array(resource&.dig("rlinks")).map { |rl| rl["href"].to_s }
    rlinks = [ href ] if resource.nil? && !href.start_with?("#")

    if (catalog = by_uuid([ href, *rlinks ]))
      return [ catalog, "uuid" ]
    end
    if (catalog = by_nist_pattern(rlinks, imp))
      return [ catalog, "nist_pattern" ]
    end
    if (catalog = by_unique_title(resource&.dig("title")))
      return [ catalog, "title" ]
    end

    [ nil, nil ]
  end

  def by_uuid(refs)
    uuids = refs.flat_map { |ref| ref.to_s.scan(UUID_PATTERN) }.map(&:downcase)
    return nil if uuids.empty?

    @catalogs.find do |c|
      ids = [ c.metadata_extra.is_a?(Hash) ? c.metadata_extra["catalog_uuid"] : nil, c.oscal_uuid ]
      (ids.compact.map { |id| id.to_s.downcase } & uuids).any?
    end
  end

  def by_nist_pattern(rlinks, imp)
    hrefs = rlinks.map(&:downcase)
    fits = @catalogs.select do |c|
      name = c.name.to_s.downcase
      catalog_rev = revision(name)
      next false unless name.include?(CATALOG_800_53) && catalog_rev

      hrefs.any? { |h| h.include?(CATALOG_800_53) && revision(h) == catalog_rev }
    end
    return fits.first if fits.size < 2
    return @preferred if @preferred && fits.any? { |c| c.id == @preferred.id }

    named = Array(imp["include-controls"]).flat_map { |ic| Array(ic["with-ids"]) }.map(&:to_s)
    # max_by keeps the first of equals, so a tie still goes to the lowest id.
    fits.max_by { |c| named.count { |id| known_ids(c).include?(id) } }
  end

  def known_ids(catalog)
    (@known_ids ||= {})[catalog.id] ||= tree_for(catalog).to_set(&:first)
  end

  def by_unique_title(title)
    wanted = title.to_s.strip.downcase
    return nil if wanted.empty?

    named = @catalogs.select { |c| c.name.to_s.strip.downcase == wanted }
    named.one? ? named.first : nil
  end

  def revision(text) = text[REV_PATTERN, 1] || text[REVISION_WORD, 1]
end
