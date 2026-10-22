# frozen_string_literal: true

# Which control a profile's `set-parameters` entry belongs to, and the id it is
# stored under. The profile JSON and XML importers both read this.
#
# They used to keep a parameter only when its id started with the control id
# plus "_". NIST's Rev 5 ids are zero-padded and the control ids are not:
# `"ac-01_odp.05".start_with?("ac-1_")` is false, so every Rev 5
# organization-defined parameter in an imported profile was dropped without a
# word. Only the Rev 4-style `ac-1_prm_1` form survived.
#
# Ownership comes from the catalog when one is linked: the control that
# declares the parameter, or declares it as an `alt-identifier` (an alias is
# stored under the parameter's real id, as the baseline-parameters endpoint
# does, #1218). Without a catalog, or for an id the catalog does not declare,
# the owner is the control prefix of the id itself, canonicalised:
# `ac-01_odp.05` -> `ac-1`, `ac-02.03_odp.01` -> `ac-2.3`, `dp-01_odp` -> `dp-1`.
#
# NIST 800-53: CM-6 (the organization-defined values a baseline sets), PL-2.
class ProfileParameterOwner
  Entry = Struct.new(:param_id, :control_id, keyword_init: true)

  # @param catalogs [ControlCatalog, Array<ControlCatalog>, nil] the profile's
  #   linked catalog, or (#1234) every catalog its imports resolved to; the
  #   first declaring a parameter id owns it
  def initialize(catalogs)
    @index = Array(catalogs).compact.reverse.reduce({}) { |index, catalog| index.merge(build_index(catalog)) }
  end

  # @return [Entry] the stored id and the canonical id of the owning control
  def resolve(param_id)
    id = param_id.to_s.strip
    @index[id] || Entry.new(param_id: id, control_id: ControlId.canonical(id.split("_").first))
  end

  # Does this parameter belong to the profile control `control_id`?
  def belongs_to?(param_id, control_id)
    resolve(param_id).control_id == ControlId.canonical(control_id)
  end

  private

  def build_index(catalog)
    index = {}
    aliases = {}
    CatalogControl.joins(:control_family)
                  .where(control_families: { control_catalog_id: catalog.id })
                  .where.not(params_data: nil)
                  .find_each do |control|
      owner = ControlId.canonical(control.control_id)
      control.params_list.each do |param|
        real = param["id"].to_s
        next if real.blank?

        index[real] = Entry.new(param_id: real, control_id: owner)
        alias_ids(param).each { |alias_id| aliases[alias_id] = Entry.new(param_id: real, control_id: owner) }
      end
    end
    # A real id always wins over an alias spelled the same way.
    aliases.merge(index)
  end

  def alias_ids(param)
    Array(param["props"]).select { |prop| prop["name"] == "alt-identifier" }.filter_map { |prop| prop["value"].presence }
  end
end
