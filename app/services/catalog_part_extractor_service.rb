# Walks an OSCAL resolved catalog hash to extract `controls[].parts[]`
# of arbitrary types (defaults to "statement"). Generalization of
# ControlObjectiveExtractorService (which handles "assessment-objective"
# parts for SAP/SAR objectives, #390); both share the catalog-walking
# primitive.
#
# Public class API (pure -- safe to call from migrations):
#
#   CatalogPartExtractorService.parts_for_control(catalog_json, "ac-1")
#     => [{part_id:, part_name:, label:, prose:, parent_part_id:, row_order:}, ...]
#
# Instance API for backfilling consumer documents:
#
#   CatalogPartExtractorService.new(ssp_doc).backfill_ssp_statements!
#   CatalogPartExtractorService.new(cdef_doc).backfill_cdef_statements!
#
# Catalog-direct backfill (no profile chain -- catalog IS the source):
#
#   CatalogPartExtractorService.backfill_catalog_parts!(control_catalog)
#
# UUID stability invariant (#397 forward-compat contract): backfilled
# UUIDs use OscalUuidService.derived(parent_control.uuid, namespace_tag,
# statement_id) so previously-exported documents round-trip with
# byte-identical statement UUIDs. Namespace tags:
#   - SSP statements:  "ssp-statement"
#   - CDEF statements: "cdef-statement"
#   - Catalog parts:   "catalog-part:<part_name>"
class CatalogPartExtractorService
  REASSOCIATION_FLAG  = "statements_backfill_status".freeze
  REASSOCIATION_VALUE = "needs_reassociation".freeze
  DEFAULT_PART_NAMES  = %w[statement item].freeze

  # `item` is not decoration. NIST names a control's statement part
  # "statement" and every one of its SUB-PARTS "item":
  #
  #     ac-1_smt        name="statement"
  #       ac-1_smt.a    name="item"
  #         ac-1_smt.a.1  name="item"
  #
  # Walking only "statement" therefore captures the CONTAINER and none of the
  # requirements inside it — measured on the shipped Rev 5 catalog, ac-1 yields
  # 1 part instead of 10. That is one half of why every SSP carried exactly one
  # implementation statement per control (#1100); the other half is that the
  # importer never stored the parts at all.
  # #1114 — `assessment-objects` is where 800-53A says WHAT to examine: the
  # policies, plans, mechanisms and personnel that constitute the evidence for a
  # method. Owner review of the assessment plan: "the assessment plan should
  # already have backmatter links for those that have them and callout control
  # parts that do not (e.g. under assessment depth would be back matter
  # reference(s) link(s))". Those references are exactly this part.
  #
  #     assessment-method  ac-1_asm-examine     prose ""
  #       assessment-objects  (NO id)           prose "Access control policy and
  #                                                    procedures; system security
  #                                                    plan; ..."
  #
  # It was dropped twice over: absent from this list, and — because NIST ships it
  # with no `id` — skipped by the `part["id"].present?` guard even if listed. See
  # `synthetic_part_id` for why an id is derived rather than the guard relaxed.
  CATALOG_PART_NAMES = %w[statement item guidance assessment-objective assessment-method
                          assessment-objects].freeze

  # Pure: returns parts of the requested types for a single control.
  def self.parts_for_control(catalog_json, control_id, part_names: DEFAULT_PART_NAMES)
    return [] if catalog_json.blank? || control_id.blank?

    target = control_id.to_s.downcase
    catalog = catalog_json.is_a?(Hash) ? (catalog_json["catalog"] || catalog_json) : {}
    control_node = find_control(catalog["groups"] || [], catalog["controls"] || [], target)
    return [] unless control_node

    parts = []
    walk_parts(control_node["parts"] || [], parts, part_names: part_names, parent_part_id: nil)
    parts.each_with_index { |p, i| p[:row_order] = i }
    parts
  end

  def self.find_control(groups, controls, target)
    controls.each do |ctrl|
      return ctrl if ctrl["id"].to_s.downcase == target
      nested = find_control([], ctrl["controls"] || [], target)
      return nested if nested
    end
    groups.each do |group|
      hit = find_control(group["groups"] || [], group["controls"] || [], target)
      return hit if hit
    end
    nil
  end

  # Recurse into the part subtree. Always recurse regardless of whether
  # this node matched -- structural wrappers commonly nest the actual
  # statements/objectives one or two levels down.
  def self.walk_parts(parts, acc, part_names:, parent_part_id:)
    parts.each_with_index do |part, index|
      next_parent = parent_part_id
      part_id = part["id"].presence || synthetic_part_id(part, parent_part_id, index)

      if part_names.include?(part["name"]) && part_id.present?
        label_prop = (part["props"] || []).find { |p| p["name"] == "label" }
        acc << {
          part_id:        part_id.to_s,
          part_name:      part["name"].to_s,
          label:          label_prop && label_prop["value"].presence,
          prose:          part["prose"].to_s.strip.presence,
          props_data:    (part["props"] || []),
          parent_part_id: parent_part_id
        }
        next_parent = part_id.to_s
      end

      walk_parts(part["parts"] || [], acc, part_names: part_names, parent_part_id: next_parent)
    end
  end

  # NIST ships `assessment-objects` with no `id`, so it cannot be stored,
  # referenced by an assessment, or linked to back-matter. The id is DERIVED from
  # its parent and position rather than the guard being relaxed: a part row is
  # addressable by construction everywhere else in this table, and a NULL id
  # would break the parent/child join the whole tree depends on.
  #
  # Deterministic, so a re-import produces the same id and the upsert stays
  # idempotent — a random id would create a duplicate row on every import.
  # Follows NIST's own suffix convention (`ac-1_asm-examine` -> its objects).
  def self.synthetic_part_id(part, parent_part_id, index)
    return nil if parent_part_id.blank?
    return nil unless part["name"].to_s == "assessment-objects"

    "#{parent_part_id}_objects#{index.positive? ? "-#{index}" : ""}"
  end

  # Catalog-direct backfill. Walks every control in the catalog and
  # populates catalog_control_parts. Idempotent on (catalog_control_id,
  # part_id).
  def self.backfill_catalog_parts!(catalog)
    rows = []
    now = Time.current
    part_names = CATALOG_PART_NAMES

    # Build the in-memory catalog hash to walk. The catalog is already in
    # the DB, but we walk via the OSCAL-style structure. ControlCatalog
    # has CatalogControl children; traverse those directly.
    catalog.catalog_controls.find_each do |cc|
      existing_part_ids = cc.catalog_control_parts.pluck(:part_id).to_set
      # Reconstruct an OSCAL-shaped control hash from the stored data.
      # guidance_data may carry the parts payload; fallback to empty.
      parts_hash = parts_from_guidance_data(cc.guidance_data)
      next if parts_hash.empty?


      control_node = { "id" => cc.control_id, "parts" => parts_hash }
      acc = []
      walk_parts(control_node["parts"], acc, part_names: part_names, parent_part_id: nil)
      acc.each_with_index do |p, idx|
        next if existing_part_ids.include?(p[:part_id])
        rows << {
          catalog_control_id: cc.id,
          uuid:               OscalUuidService.derived(cc.uuid, "catalog-part:#{p[:part_name]}", p[:part_id]),
          part_id:            p[:part_id],
          part_name:          p[:part_name],
          label:              p[:label],
          parent_part_id:     p[:parent_part_id],
          prose:              p[:prose],
          props_data:         p[:props_data] || [],
          row_order:          idx,
          created_at:         now,
          updated_at:         now
        }
      end
    end

    CatalogControlPart.insert_all(rows) if rows.any?
    rows.size
  end

  # Defensive: guidance_data may be a JSON string or Hash; might contain
  # "parts" array directly or be empty.
  def self.parts_from_guidance_data(raw)
    return [] if raw.blank?
    parsed = raw.is_a?(String) ? (JSON.parse(raw) rescue {}) : raw
    return [] unless parsed.is_a?(Hash)
    Array(parsed["parts"])
  end

  def initialize(document)
    @document = document
  end

  def backfill_ssp_statements!
    backfill!(:ssp_control_statements, "ssp-statement", SspControlStatement)
  end

  def backfill_cdef_statements!
    backfill!(:cdef_control_statements, "cdef-statement", CdefControlStatement)
  end

  private

  def backfill!(association_name, namespace_tag, klass)
    catalog = resolve_catalog
    if catalog.blank?
      flag_needs_reassociation
      return 0
    end

    rows = []
    now = Time.current
    parent_fk = (klass == SspControlStatement) ? :ssp_control_id : :cdef_control_id
    parent_assoc = (klass == SspControlStatement) ? :ssp_controls : :cdef_controls

    @document.public_send(parent_assoc).includes(association_name).find_each do |control|
      # ADDITIVE, not all-or-nothing. This used to skip any control that already
      # had statements — and after #1100 every existing document has exactly
      # one (`<control-id>_smt`), so the whole backfill would no-op on precisely
      # the documents that need it.
      #
      # Existing rows are LEFT ALONE. A statement may already carry
      # implementation_prose an author wrote, and replacing it to tidy the shape
      # would destroy the content this feature exists to hold.
      existing = control.public_send(association_name).map(&:statement_id).to_set

      parts = self.class.parts_for_control(catalog, control.control_id)
      # A profile's `resolved_catalog_json` is CACHED, and every profile resolved
      # before #1100 holds the FLATTENED single statement — the resolver only
      # started emitting the tree in this bundle. Nothing re-resolves an existing
      # profile, so backfilling from that JSON gives every existing SSP exactly
      # one statement per control and the per-statement editor has nothing to
      # edit. Fall back to `catalog_control_parts`, which the importer now
      # populates and which is the authoritative store.
      parts = stored_parts_for(control.control_id) if parts.size <= 1

      parts.each do |part|
        next if existing.include?(part[:part_id])

        rows << {
          parent_fk            => control.id,
          uuid:                   OscalUuidService.derived(control.uuid, namespace_tag, part[:part_id]),
          statement_id:           part[:part_id],
          label:                  part[:label],
          parent_statement_id:    part[:parent_part_id],
          implementation_prose:   nil,                  # consumer authors this
          row_order:              part[:row_order],
          created_at:             now,
          updated_at:             now
        }
      end
    end

    if rows.empty?
      flag_needs_reassociation
      return 0
    end

    klass.insert_all(rows)
    clear_reassociation_flag
    rows.size
  end

  # Statement/item parts straight from the table the importer populates, in the
  # same shape `parts_for_control` returns so the caller cannot tell them apart.
  def stored_parts_for(control_id)
    catalog = source_catalog
    return [] if catalog.blank? || control_id.blank?

    ctrl = CatalogControl.joins(:control_family)
                         .where(control_families: { control_catalog_id: catalog.id })
                         .find_by("LOWER(catalog_controls.control_id) = ?", control_id.to_s.downcase)
    return [] unless ctrl

    ctrl.catalog_control_parts
        .where(part_name: DEFAULT_PART_NAMES)
        .order(:row_order)
        .map do |p|
          { part_id: p.part_id, parent_part_id: p.parent_part_id,
            label: p.label, prose: p.prose, row_order: p.row_order }
        end
  end

  def source_catalog
    profile_id = @document.try(:profile_document_id)
    if profile_id.blank? && @document.respond_to?(:ssp_document_id) && @document.ssp_document_id.present?
      profile_id = SspDocument.find_by(id: @document.ssp_document_id)&.profile_document_id
    end
    ProfileDocument.find_by(id: profile_id)&.control_catalog
  end

  def resolve_catalog
    profile_id = @document.try(:profile_document_id)
    if profile_id.blank? && @document.respond_to?(:ssp_document_id)
      ssp_id = @document.ssp_document_id
      ssp = SspDocument.find_by(id: ssp_id) if ssp_id.present?
      profile_id = ssp&.profile_document_id
    end
    return nil if profile_id.blank?
    ProfileDocument.find_by(id: profile_id)&.resolved_catalog_json
  end

  def flag_needs_reassociation
    metadata = @document.import_metadata || {}
    return if metadata[REASSOCIATION_FLAG] == REASSOCIATION_VALUE
    @document.update_column(:import_metadata, metadata.merge(REASSOCIATION_FLAG => REASSOCIATION_VALUE))
  end

  def clear_reassociation_flag
    metadata = @document.import_metadata || {}
    return unless metadata.key?(REASSOCIATION_FLAG)
    @document.update_column(:import_metadata, metadata.except(REASSOCIATION_FLAG))
  end
end
