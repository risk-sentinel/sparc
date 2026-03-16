class CatalogControl < ApplicationRecord
  belongs_to :control_family

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

  validates :control_id, presence: true, uniqueness: { scope: :control_family_id }

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

  # Returns only populated guidance fields as { field_name => value }.
  def guidance_fields
    data = parsed_guidance_data
    return {} if data.blank?
    data.select { |k, v| GUIDANCE_FIELDS.include?(k) && v.present? }
  end

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
    referenced_ids = (title.to_s.scan(/\{\{\s*insert:\s*param,\s*([^}\s]+)\s*\}\}/).flatten)
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
