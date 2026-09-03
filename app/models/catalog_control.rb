class CatalogControl < ApplicationRecord
  include ControlOrdering
  belongs_to :control_family
  has_many :ksi_validations, dependent: :destroy
  has_many :catalog_control_parts, dependent: :delete_all
  has_many :control_back_matter_links, as: :linkable, dependent: :destroy
  has_many :back_matter_resources, through: :control_back_matter_links

  # Structured guidance fields stored in the guidance_data JSONB column.
  # These come from the providing catalog (e.g. r5.json / r4_final.json) and
  # are shown read-only as context for implementors completing the SSP.
  GUIDANCE_FIELDS = %w[
    supplemental_guidance
    implementation_guidance
    check
    fix
    related_controls
    org_ref
    nist_references
  ].freeze

  BASELINE_LEVELS = %w[LOW MODERATE HIGH].freeze

  # ── API-writable guidance schema (#895) ───────────────────────────────────
  #
  # `guidance_data` is a free-form JSONB column and the web form permits it as
  # `guidance_data: {}` — an arbitrary hash. That is tolerable for a form
  # posting a known set of inputs. It is NOT tolerable on a public endpoint:
  # every OSCAL exporter reads this column, so an unenumerated key travels
  # straight into a delivered artefact. Adding a key here is a decision.
  #
  # `statement` is the verbatim catalog statement (carrying `{{ insert: param }}`
  # markup); `assessment_objective` is the SP 800-53A objective prose. Neither
  # is in GUIDANCE_FIELDS above, which lists only the *extra* fields the edit
  # form surfaces — but both are written by CatalogImportService and read by
  # the exporters, so both are writable.
  PROSE_GUIDANCE_KEYS = (%w[statement assessment_objective] + GUIDANCE_FIELDS).freeze

  # SP 800-53A assessment methods: [{ "method" => "EXAMINE", "objects" => "…" }]
  ASSESSMENT_KEYS = %w[method objects].freeze

  # FedRAMP KSI catalogs carry three extra keys, read by
  # Api::V1::KsiCatalogController. They belong to the same column, so leaving
  # them out would make a KSI catalog unmanageable over the API.
  KSI_GUIDANCE_KEYS = %w[automation_required evidence_type validation_frequency].freeze

  # Strong-parameters filter for `guidance_data`.
  def self.guidance_params_filter
    PROSE_GUIDANCE_KEYS + KSI_GUIDANCE_KEYS + [ { assessment: ASSESSMENT_KEYS } ]
  end

  # Strong-parameters filter for `params_data` — OSCAL parameter (ODP)
  # definitions. Shape taken from the seeded catalogs rather than invented:
  # `id`, `label`, `class`, `depends-on`, `props[]`, `guidelines[]`, `select`.
  # OSCAL spells two of these with hyphens; they stay spelled that way so the
  # payload matches the artefact.
  def self.params_data_filter
    [
      :id, :label, :class, "depends-on",
      {
        props: [ :name, :value, :class, :ns, :uuid, :remarks ],
        guidelines: [ :prose ],
        select: [ "how-many", { choice: [] } ],
        values: []
      }
    ]
  end

  validates :control_id, presence: true, uniqueness: { scope: :control_family_id }

  # ── URL identity (#881) ───────────────────────────────────────────────────
  #
  # `canonical_id` is the LOOKUP KEY behind
  # `/control_catalogs/<slug>/controls/ac-19.4.b.1`. It stores
  # `ControlId.canonical(control_id)` — the same form #852 established and every
  # OSCAL exporter already writes as `control-id`, so the URL agrees with the
  # artefact instead of inventing a second identity.
  #
  # It is not a new identity and nothing outside routing/lookup should read it;
  # callers wanting the canonical form keep calling ControlId.canonical.
  #
  # Statement sub-parts are first-class rows here (1936 of 4054 in the seeded
  # catalogs), so they need identifiers too — which is what makes the canonical
  # form necessary rather than cosmetic: `ac-19.4.(b).(1)` is not usable in a
  # path, `ac-19.4.b.1` is.
  before_validation :assign_canonical_id

  # The value to put in a URL. Falls back to computing it so links resolve
  # during the window between the schema migration and the deferred backfill
  # (20260802140100), and for any row written by a path that skipped callbacks.
  def canonical_identifier
    canonical_id.presence || ControlId.canonical(control_id)
  end

  # ── Control hierarchy (#881) ──────────────────────────────────────────────
  #
  # OSCAL control ids encode their own tree: `ac-1` has statement parts `ac-1a`,
  # `ac-1a.1` and enhancement `ac-1.1`. A naive prefix match is WRONG — `ac-10`
  # also starts with `ac-1` and is a completely separate control. The rule is
  # that a descendant's remainder must begin with a non-digit; a digit means the
  # base number itself differs (1 vs 10).
  #
  # Depth reproduces the counting the family view has always used, moved here so
  # there is one definition rather than a lambda in a template.
  def self.control_depth(id)
    suffix = id.to_s.sub(/\A[a-z]+-\d+(\.\d+)?/i, "")
    suffix.blank? ? 0 : suffix.scan(/[a-z]|\.\d+|\.\([^)]+\)/).size
  end

  def self.descendant?(candidate_id, ancestor_id)
    candidate = candidate_id.to_s
    ancestor  = ancestor_id.to_s
    return false if candidate == ancestor || ancestor.blank?
    return false unless candidate.start_with?(ancestor)

    # `ac-10` vs `ac-1`: the next character is a digit, so this is a different
    # control, not a child.
    !candidate[ancestor.length].match?(/\d/)
  end

  def depth = self.class.control_depth(control_id)

  def descendant_of?(other) = self.class.descendant?(control_id, other.to_s)

  # Direct children only — one level down. Deeper parts are reached by walking
  # into the child, which is what makes every sub-part addressable.
  def direct_children
    own_depth = depth
    self.class.unscoped
        .where(control_family_id: control_family_id)
        .where("control_id LIKE ?", "#{control_id}%")
        .reject { |c| c.id == id }
        .select { |c| c.descendant_of?(control_id) && c.depth == own_depth + 1 }
        .sort_by(&:control_id)
  end

  # Group catalog controls under the parents they are sub-parts of (#1002).
  #
  # Extracted from ProfileDocumentsController, which had the only copy. The SSP
  # screen needed the same grouping and `direct_children` is not it: that
  # returns ONE level, while these screens show the whole statement — ac-1a and
  # ac-1a.1 both. Two hand-written versions of this rule is how the SSP screen
  # came to render no sub-parts at all, so there is now one.
  #
  # A sub-part id is a parent id followed by a lowercase letter (ac-1 -> ac-1a
  # -> ac-1a.1). Parents are matched longest-first so ac-1 does not claim a
  # control that belongs to a longer parent id.
  #
  # @param controls [Enumerable<CatalogControl>] candidates, already loaded
  # @param parent_ids [Enumerable<String>] the control ids being displayed
  # @return [Hash{String => Array<CatalogControl>}] parent id => its sub-parts
  def self.sub_parts_by_parent(controls, parent_ids)
    parents = Array(parent_ids).to_set
    longest_first = parents.sort_by { |id| -id.length }

    controls.each_with_object({}) do |cc, acc|
      next if parents.include?(cc.control_id)

      parent = longest_first.find { |pid|
        cc.control_id.start_with?(pid) &&
        cc.control_id.length > pid.length &&
        cc.control_id[pid.length]&.match?(/[a-z]/)
      }
      (acc[parent] ||= []) << cc if parent
    end
  end

  def to_param = canonical_identifier

  # Resolve a control within a catalog by its canonical identifier.
  #
  # `(catalog, canonical_id)` is unique — verified across all 4054 seeded
  # controls — which is why the family need not appear in the path.
  #
  # The linear fallback exists only for the backfill window; it is bounded by
  # one catalog's controls and disappears once canonical_id is populated.
  # ── The one answer to "is this a real control?" (#911) ────────────────────
  #
  # Catalogs are the source of truth every other document depends on, so the
  # existence check belongs here rather than in each consumer. `ControlId`
  # (#852) owns the three *forms* an identifier can take; this owns whether one
  # of them names something real.
  #
  # Cross-catalog and form-agnostic on purpose: a caller (an SSP, a control
  # mapping, an evidence link) usually holds an identifier a human typed, in
  # whichever form they saw, and no particular catalog in mind. That differs
  # from `find_by_canonical`, which resolves *within* one catalog and expects an
  # already-canonical id.
  #
  # Every consumer goes through here. #852 exists because a dozen private copies
  # of identifier logic disagreed with each other; an existence check duplicated
  # per model would rot the same way.
  def self.resolve(raw)
    canonical = ControlId.canonical(raw)
    return nil if canonical.blank? || canonical == "unknown"

    where(control_id: canonical).or(where(canonical_id: canonical))
      .includes(:control_family).first
  end

  # Boolean form, for callers that do not need the record.
  def self.resolvable?(raw) = resolve(raw).present?

  def self.find_by_canonical(catalog, identifier)
    return nil if catalog.nil? || identifier.blank?

    scope = joins(control_family: :control_catalog)
              .where(control_families: { control_catalog_id: catalog.id })

    scope.find_by(canonical_id: identifier) ||
      scope.detect { |control| control.canonical_identifier == identifier }
  end

  default_scope { order(Arel.sql("COALESCE(sort_id, control_id)")) }

  # Scope to only base controls (e.g. "ac-1") and enhancements (e.g. "ac-2.1"),
  # excluding statement sub-parts like "ac-1a", "ac-1a.1", "ac-1a.1.(a)".
  # OSCAL base/enhancement IDs match: letter(s) + dash + digits + optional .digits
  scope :top_level, -> { where("control_id ~ ?", '^[a-z]+-[0-9]+(\\.[0-9]+)?$') }

  # Returns the human-readable label (e.g., "AC-1", "AC-2(1)") or falls back to
  # the canonical OSCAL id (e.g., "ac-1", "ac-2.1") when no label is stored.
  def display_id
    label.presence || control_id
  end

  def family_code
    control_family.code
  end

  # Returns true when at least one guidance field has content.
  def guidance_present?
    data = parsed_guidance_data
    return false if data.blank?
    GUIDANCE_FIELDS.any? { |f| data[f].present? }
  end

  # The whole guidance_data document, parsed. `guidance_fields` below returns
  # only the subset the edit form surfaces as "additional" fields; API callers
  # need all of it, including `statement` and the assessment structures.
  def guidance_hash = parsed_guidance_data

  # Returns only populated guidance fields as { field_name => value }.
  def guidance_fields
    data = parsed_guidance_data
    return {} if data.blank?
    data.select { |k, v| GUIDANCE_FIELDS.include?(k) && v.present? }
  end

  # Drop blank values so an empty field is an absent key rather than an empty
  # string in a delivered OSCAL artefact — but keep `false`, which is a value
  # (the KSI keys are booleans) and not an absence.
  def self.normalize_guidance(incoming)
    (incoming || {}).each_with_object({}) do |(key, value), out|
      next if value != false && value.blank?

      out[key.to_s] = value
    end
  end

  # PATCH semantics for `guidance_data` (#895).
  #
  # Assigning the column wholesale would silently drop every key the caller did
  # not resend: a partial update of `statement` would take `supplemental_guidance`
  # with it, and the loss would only surface in an OSCAL export weeks later.
  # Merge instead. A key sent as `null` or `""` is deleted, so a caller can still
  # remove one without having to resend the whole document.
  def merge_guidance_data(incoming)
    existing = parsed_guidance_data.dup
    return existing if incoming.blank?

    incoming.each do |key, value|
      # `false` is a value, not an absence — the KSI keys are booleans.
      if value == false
        existing[key.to_s] = false
      elsif value.blank?
        existing.delete(key.to_s)
      else
        existing[key.to_s] = value
      end
    end
    existing
  end

  # ── Control-level OSCAL links (#999) ──────────────────────────────────────
  #
  # Stored verbatim by CatalogImportService so a catalog round-trips: the Rev 5
  # source carries five rels — `reference` (into back-matter), `related`,
  # `required`, and `incorporated-into` / `moved-to`, which record where a
  # WITHDRAWN control went and are recoverable from nothing else SPARC keeps.
  #
  # `reference` links are additionally joined to promoted BackMatterResource
  # rows, so an exported `#uuid` href resolves; this column stays the archival
  # record of what the source file said.
  def links_list
    raw = links_data
    return [] if raw.blank?

    result = raw.is_a?(String) ? JSON.parse(raw) : raw
    result.is_a?(Array) ? result : []
  rescue JSON::ParserError
    []
  end

  def links_present? = links_list.present?

  # Returns true when at least one parameter definition exists.
  def params_present?
    params_list.present?
  end

  # Returns the parsed params array, handling String (double-encoded) vs Array.
  def params_list
    raw = params_data
    return [] if raw.blank?
    result = raw.is_a?(String) ? JSON.parse(raw) : raw
    result.is_a?(Array) ? result : []
  rescue JSON::ParserError
    []
  end

  # Returns params for this control, falling back to the parent control's params
  # when this is a sub-control (e.g. "ac-1a") that references parameters defined
  # on its parent (e.g. "ac-1") via {{ insert: param, ... }} template markup.
  def effective_params_list
    own = params_list
    return own if own.present?

    # Extract param IDs referenced in the title via {{ insert: param, <id> }}
    referenced_ids = OscalParamReference.ids(title)
    return [] if referenced_ids.empty?

    # Determine parent control ID: strip the trailing sub-part suffix to get the base
    parent_id = control_id.match(/\A([a-z]+-\d+(?:\.\d+)*)/i)&.[](1)
    return [] if parent_id.blank? || parent_id == control_id

    parent = self.class.unscoped.find_by(control_family_id: control_family_id, control_id: parent_id)
    return [] unless parent

    # Return only the parent params that are actually referenced by this sub-control
    parent.params_list.select { |p| referenced_ids.include?(p["id"]) }
  end

  # Merges a hash of { param_id => new_label } into the params_data array.
  # Only the "label" key is updated; all other param fields (id, select,
  # guidelines, props) are preserved.  Returns the updated array.
  def merge_params_labels(labels_hash)
    return params_list if labels_hash.blank?

    params_list.map do |param|
      if labels_hash.key?(param["id"])
        new_label = labels_hash[param["id"]].presence
        new_label ? param.merge("label" => new_label) : param.except("label")
      else
        param
      end
    end
  end

  # ── Baseline helpers ─────────────────────────────────────────────
  # baseline_impact can be stored in two formats:
  #   - Full names, comma-separated: "LOW, MODERATE, HIGH"
  #   - Abbreviated, space-separated: "L M H"
  # Both are normalized to full uppercase names on read.

  BASELINE_ABBREVIATIONS = { "L" => "LOW", "M" => "MODERATE", "H" => "HIGH" }.freeze

  # Returns an array of uppercase baseline levels, e.g. ["LOW", "MODERATE"].
  def baseline_levels
    raw = baseline_impact.to_s.strip
    return [] if raw.blank?

    # Detect format: if it contains commas, split by comma; otherwise split by space
    tokens = if raw.include?(",")
      raw.split(/\s*,\s*/)
    else
      raw.split(/\s+/)
    end

    tokens.map(&:strip).reject(&:blank?).map { |t| BASELINE_ABBREVIATIONS[t.upcase] || t.upcase }
  end

  # Returns true when the control includes the given level.
  def has_baseline_level?(level)
    baseline_levels.include?(level.to_s.upcase)
  end

  # Adds a baseline level without duplicates; updates baseline_impact in memory.
  def add_baseline_level(level)
    levels = baseline_levels
    levels << level.to_s.upcase unless levels.include?(level.to_s.upcase)
    self.baseline_impact = levels.join(", ")
  end

  # Removes a baseline level; sets baseline_impact to nil when empty.
  def remove_baseline_level(level)
    levels = baseline_levels - [ level.to_s.upcase ]
    self.baseline_impact = levels.any? ? levels.join(", ") : nil
  end

  private

  # #881 — keep the URL identifier in step with control_id on every write.
  def assign_canonical_id
    return if control_id.blank?

    self.canonical_id = ControlId.canonical(control_id)
  end

  # update_all bypasses ActiveRecord type casting, so guidance_data can
  # arrive from the DB as a plain String (double-encoded JSON) rather than
  # a Hash.  Parse defensively to handle both cases.
  def parsed_guidance_data
    raw = guidance_data
    return {} if raw.blank?
    raw.is_a?(String) ? JSON.parse(raw) : raw
  rescue JSON::ParserError
    {}
  end
end
