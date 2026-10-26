# frozen_string_literal: true

# A person confirms, selects or changes the catalog a baseline's controls come
# from, and the baseline is re-checked against it.
#
# Upload matches each import to a loaded catalog (ProfileImportCatalogResolver)
# and records the result, but a match by name is a guess: a profile whose
# links say "SP 800-53 rev5" fits NIST's catalog and an agency overlay named
# "... SP 800-53 Rev 5" alike. So a matched baseline starts PENDING, and stays
# unpublishable until someone confirms or picks its catalog here.
#
# Picking used to set `control_catalog_id` and nothing else. The import record
# kept the catalog upload had guessed, so the page went on warning that the
# baseline "names controls its catalog does not have", listing every control,
# and each control kept the wrong source catalog.
#
# What changes, for each import the chosen catalog now covers:
#   - its catalog, and how it was matched ("selected");
#   - the controls it selects, re-read against the chosen catalog's tree,
#     and the ids that catalog does not hold;
#   - each existing control's source catalog, and a missing title.
# An import matched by catalog uuid keeps its catalog: the profile named it.
# Nothing a person entered is touched: parameter values, priorities and notes
# live on the controls, which are updated in place and never deleted.
#
# A control the chosen catalog newly selects (an `include-all` import that
# matched nothing at upload) is reported, not created: its parameter values
# are in the uploaded file, so importing the baseline again is what adds it
# completely.
class ProfileCatalogLinkService
  Result = Struct.new(:retargeted, :not_added, keyword_init: true)

  def initialize(profile)
    @profile = profile
    @catalog = profile.control_catalog
  end

  def call
    return Result.new(retargeted: 0, not_added: []) unless @catalog

    records  = Array(@profile.import_metadata&.dig("imports")).map(&:dup)
    retarget = indexes_to_retarget(records)
    not_added = []

    ProfileDocument.transaction do
      retarget.each do |index|
        record = records[index]
        import = source_import(record, index)
        record["catalog_id"]   = @catalog.id
        record["matched_by"]   = "selected"
        record["control_ids"]  = selection.select(import)
        record["unknown_ids"]  = selection.unknown_ids(import).presence
        record.delete("unresolved_selectors")
        record.compact!
        not_added.concat(relink_controls(record["control_ids"]))
      end

      @profile.update_columns(import_metadata: metadata_with(records))
    end

    Result.new(retargeted: retarget.size, not_added: not_added.uniq)
  end

  private

  # Every import not named by catalog uuid that the chosen catalog covers: it
  # holds at least one of the import's controls, or the import is the only one
  # the profile did not name by uuid (an `include-all` import names none).
  def indexes_to_retarget(records)
    open = records.each_index.reject { |i| records[i]["matched_by"] == "uuid" }
    open.select do |i|
      named = Array(records[i]["control_ids"]) + Array(records[i]["unknown_ids"])
      named.any? { |id| known_ids.include?(id) } || open.one?
    end
  end

  # The import as uploaded, saved at upload since this change; for an older
  # baseline, the ids it was recorded as naming.
  def source_import(record, index)
    raw = Array(@profile.import_metadata&.dig("source_imports"))[index]
    return raw if raw.is_a?(Hash)

    { "include-controls" => [ { "with-ids" => Array(record["control_ids"]) + Array(record["unknown_ids"]) } ] }
  end

  # Points the baseline's existing controls at the chosen catalog, titles any
  # that have none, and returns the selected ids it has no control for.
  def relink_controls(control_ids)
    existing = @profile.profile_controls.where(control_id: control_ids).index_by(&:control_id)
    existing.each_value do |control|
      attrs = { source_catalog_id: @catalog.id }
      attrs[:title] = catalog_titles[control.control_id] if control.title.blank? && catalog_titles[control.control_id]
      control.update_columns(attrs)
    end
    control_ids - existing.keys
  end

  def metadata_with(records)
    (@profile.import_metadata || {}).merge(
      "imports" => records,
      "unlinked_imports" => records.reject { |r| r["catalog_id"] }.map { |r| r.slice("href", "title", "control_ids", "unresolved_selectors") }.presence,
      "catalog_confirmation" => "confirmed"
    ).compact
  end

  def tree = @tree ||= CatalogControlTree.for(@catalog)
  def selection = @selection ||= ProfileSelection.new(tree)
  def known_ids = @known_ids ||= tree.to_set(&:first)

  def catalog_titles
    @catalog_titles ||= CatalogControl.unscoped.joins(:control_family)
                                      .where(control_families: { control_catalog_id: @catalog.id })
                                      .pluck(:control_id, :title).to_h
  end
end
