# frozen_string_literal: true

# #1218 — builds the organization-defined parameter (ODP) worksheets published
# under docs/api/samples/: one for the whole NIST SP 800-53 Rev 5 catalog and
# one for each of the LOW, MODERATE and HIGH baselines.
#
# A worksheet IS a request body. It is the shape
# `PUT /api/v1/profile_documents/:id/parameters` and the parameter file import
# (`.../parameters/import/preview` → `/confirm`) both accept — top-level
# `parameters` and `selections` arrays — so a team fills in the values it has
# decided and sends the file as it stands:
#
# * every entry starts as `value: null` / `selected: null`, which the API reads
#   as "not provided" and skips, so the entries a team leaves alone do not
#   blank what is already stored;
# * the ids are the catalog's own (`ac-01_odp.03`), with the Rev 4-style id NIST
#   kept as an `alt-identifier` (`ac-1_prm_2`) alongside for reference;
# * everything else on an entry (control, label, guidance, choices) is
#   reference material the API ignores.
#
# Aggregate parameters — `ac-1_prm_1`, declared by NIST as the union of
# `ac-01_odp.01` and `ac-01_odp.02` — are left out. Their value is composed from
# the ODPs they aggregate; setting one separately stores a value that can
# disagree with its own parts.
#
# Regenerate with `bin/rails samples:odp_worksheets`;
# spec/lib/odp_worksheet_builder_spec.rb fails when the committed files drift.
class OdpWorksheetBuilder
  CATALOG = "lib/data/catalogs/NIST_SP-800-53_rev5_catalog.json"
  # NIST's own baseline profiles, as published (OSCAL content v5.2.0).
  BASELINES = {
    "low"      => "spec/fixtures/files/profiles/NIST_SP-800-53_rev5_LOW-baseline_profile.json",
    "moderate" => "spec/fixtures/files/profiles/NIST_SP-800-53_rev5_MODERATE-baseline_profile.json",
    "high"     => "spec/fixtures/files/profiles/NIST_SP-800-53_rev5_HIGH-baseline_profile.json"
  }.freeze
  OUTPUT_DIR = "docs/api/samples"
  INSERT_PARAM = /\{\{\s*insert:\s*param,\s*([^}\s]+)\s*\}\}/

  def initialize(root: Rails.root)
    @root = Pathname(root)
  end

  # @return [Hash{String => Hash}] file name => worksheet
  def worksheets
    sheets = { "rev5-catalog-odp.json" => build(nil, "NIST SP 800-53 Rev 5 — every organization-defined parameter") }
    BASELINES.each do |level, path|
      ids = baseline_control_ids(path)
      sheets["rev5-#{level}-odp.json"] =
        build(ids, "NIST SP 800-53 Rev 5 #{level.upcase} baseline — organization-defined parameters", level: level)
    end
    sheets
  end

  # Serialised exactly as committed, so the drift spec compares bytes.
  def render(worksheet) = "#{JSON.pretty_generate(worksheet)}\n"

  def write!
    worksheets.each do |name, sheet|
      @root.join(OUTPUT_DIR, name).write(render(sheet))
    end
  end

  private

  def catalog
    @catalog ||= JSON.parse(@root.join(CATALOG).read)["catalog"]
  end

  def controls
    @controls ||= catalog["groups"].flat_map { |group| flatten(group["controls"]) }
  end

  def flatten(list)
    Array(list).flat_map { |control| [ control, *flatten(control["controls"]) ] }
  end

  def baseline_control_ids(path)
    profile = JSON.parse(@root.join(path).read)["profile"]
    profile["imports"].flat_map { |imp| Array(imp["include-controls"]).flat_map { |inc| Array(inc["with-ids"]) } }.to_set
  end

  def build(control_ids, title, level: nil)
    parameters = []
    selections = []
    omitted = 0

    controls.each do |control|
      next if control_ids && !control_ids.include?(control["id"])

      Array(control["params"]).each do |param|
        if prop_values(param, "aggregates").any?
          omitted += 1
          next
        end

        reference = {
          "control_id" => control["id"],
          "control_title" => control["title"],
          "label" => param["label"],
          "guidance" => Array(param["guidelines"]).filter_map { |g| g["prose"] }.join(" ").presence,
          "assessment_label" => prop_values(param, "label").first,
          "alt_identifier" => prop_values(param, "alt-identifier").first
        }.compact

        if param["select"]
          choices = Array(param["select"]["choice"])
          depends_on = choices.flat_map { |choice| choice.scan(INSERT_PARAM).flatten }.uniq.sort
          selections << { "select_id" => param["id"], "selected" => nil, **reference,
                          "how_many" => param["select"]["how-many"] || "one",
                          "choices" => choices,
                          **(depends_on.any? ? { "depends_on" => depends_on } : {}) }
        else
          parameters << { "param_id" => param["id"], "value" => nil, **reference }
        end
      end
    end

    {
      "_about" => {
        "title" => title,
        "source" => [ "NIST SP 800-53 Rev 5 catalog v#{catalog.dig('metadata', 'version')}",
                      (level && "NIST #{level.upcase} baseline profile") ].compact.join(", "),
        "how_to_use" => "Set `value` (parameters) or `selected` (selections, an array of choices) for the " \
                        "entries you have decided, then send this file unchanged to " \
                        "PUT /api/v1/profile_documents/:id/parameters, or upload it to " \
                        ".../parameters/import/preview and .../import/confirm. Entries left null are skipped; " \
                        "\"\" or [] clears a stored value. Every other key is reference and is ignored.",
        "controls" => control_ids ? control_ids.size : controls.size,
        "parameters" => parameters.size,
        "selections" => selections.size,
        "aggregate_parameters_omitted" => omitted
      },
      "parameters" => parameters,
      "selections" => selections
    }
  end

  def prop_values(param, name)
    Array(param["props"]).select { |prop| prop["name"] == name }.filter_map { |prop| prop["value"] }
  end
end
