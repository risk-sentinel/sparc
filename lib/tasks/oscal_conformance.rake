# OSCAL conformance dataset (#1106).
#
# `OscalSchemaValidationService` validates JSON Schema, which checks SHAPE. It
# cannot check that a prop name means what a conforming reader will think it
# means, that a value comes from the vocabulary it claims, or that an identifier
# resolves to anything. Those rules live in NIST's **Metaschema** as
# `allowed-values`, `has-cardinality`, `index-has-key` and `is-unique` — none of
# which survive the translation to JSON Schema or XSD. Measured: `EXAMINE`,
# `sort-id`, `control-origination` and `sp-corporate` appear in ZERO of the eight
# baked-in XSDs.
#
# This task bakes those rules into `lib/oscal_conformance/<version>/` so the
# conformance check runs offline, in CI, against the version a document declares.
#
# Two things it does NOT do, both deliberate:
#
#   * It does not scrape https://pages.nist.gov/OSCAL-Reference/models/{ver}/…
#     Those pages are GENERATED from this metaschema. Fetching them was tried and
#     returned a confidently wrong answer after truncating mid-page.
#   * It does not hardcode which metaschema files feed which model. It resolves
#     `<import>` transitively and `<!ENTITY … SYSTEM>` includes, because the set
#     moves between versions — `label` and `sort-id` appear ZERO times in
#     catalog.xml; they arrive via control-common.
#
# Usage:
#   bin/rails oscal:bundle_conformance          # DEFAULT_VERSION
#   bin/rails oscal:bundle_conformance[1.2.3]
#   bin/rails oscal:bundle_conformance[all]     # every SUPPORTED_VERSION
namespace :oscal do
  METASCHEMA_BASE = "https://raw.githubusercontent.com/usnistgov/OSCAL".freeze

  # The eight models SPARC exports. Values are the ROOT metaschema basename;
  # everything else is discovered through <import>.
  CONFORMANCE_MODELS = {
    "catalog" => "oscal_catalog_metaschema.xml",
    "profile" => "oscal_profile_metaschema.xml",
    "component-definition" => "oscal_component_metaschema.xml",
    "system-security-plan" => "oscal_ssp_metaschema.xml",
    "assessment-plan" => "oscal_assessment-plan_metaschema.xml",
    "assessment-results" => "oscal_assessment-results_metaschema.xml",
    "plan-of-action-and-milestones" => "oscal_poam_metaschema.xml",
    "mapping" => "oscal_mapping_metaschema.xml"
  }.freeze

  desc "Bundle the NIST Metaschema conformance dataset to lib/oscal_conformance/<ver>/ (#1106)"
  task :bundle_conformance, [ :version ] => :environment do |_t, args|
    requested = args[:version].presence || OscalSchema::DEFAULT_VERSION
    versions  = requested == "all" ? OscalSchema::SUPPORTED_VERSIONS : [ requested ]

    versions.each { |version| bundle_conformance_for(version) }
  end

  def bundle_conformance_for(version)
    oscal_log "OSCAL conformance dataset — v#{version}"
    cache = {}
    dataset = {
      "oscal_version" => version,
      "generated_from" => "#{METASCHEMA_BASE}/tree/v#{version}/src/metaschema",
      "models" => {}
    }

    CONFORMANCE_MODELS.each do |model, root|
      begin
        sources = resolve_metaschema_closure(version, root, cache)
      rescue StandardError => e
        # Not every model exists in every version — Mapping arrived in 1.2.0,
        # which is why OscalSchema::MAPPING_VERSIONS exists. Skip and say so,
        # rather than aborting the version: a missing model must not cost us the
        # seven that ARE there.
        oscal_log format("  %-32s SKIPPED — not in v%s (%s)", model, version, e.class)
        next
      end

      dataset["models"][model] = extract_model_rules(sources).merge("metaschemas" => sources.keys.sort)
      counts = dataset["models"][model]
      oscal_log format("  %-32s %2d files  %3d prop-names  %3d vocabularies  %3d cardinalities",
                       model, sources.size,
                       counts["prop_names"].size, counts["prop_values"].size, counts["cardinalities"].size)
    end

    dataset["role_ids"] = dataset["models"]
      .values.flat_map { |m| m["role_ids"] }.uniq.sort

    dir = Rails.root.join("lib", "oscal_conformance", version)
    FileUtils.mkdir_p(dir)
    File.write(dir.join("conformance.json"), JSON.pretty_generate(dataset) + "\n")
    oscal_log "  -> #{dir.relative_path_from(Rails.root)}/conformance.json " \
              "(#{dataset['role_ids'].size} NIST role ids)"
    oscal_log
  end

  # Fetch a metaschema and everything it <import>s, transitively. Entity
  # includes (`<!ENTITY x SYSTEM "./shared-constraints/….ent">`) are expanded in
  # place — that is how NIST ships the responsible-role vocabularies, and a
  # parser that ignores them silently loses every role id.
  def resolve_metaschema_closure(version, root, cache, acc = {})
    return acc if acc.key?(root)

    body = cache[[ version, root ]] ||= fetch_following_redirects(
      "#{METASCHEMA_BASE}/v#{version}/src/metaschema/#{root}"
    )
    body = expand_entities(version, body, cache)
    acc[root] = body

    body.scan(/<import\s+href="([^"]+)"/).flatten.each do |href|
      next unless href.end_with?(".xml")

      resolve_metaschema_closure(version, File.basename(href), cache, acc)
    end
    acc
  end

  def expand_entities(version, body, cache)
    body.scan(/<!ENTITY\s+(\S+)\s+SYSTEM\s+"([^"]+)"/).each do |name, path|
      content = cache[[ version, path ]] ||= fetch_following_redirects(
        "#{METASCHEMA_BASE}/v#{version}/src/metaschema/#{path.delete_prefix('./')}"
      )
      body = body.gsub("&#{name};", content)
    rescue StandardError => e
      oscal_log "  WARNING: entity #{name} (#{path}) not resolved — #{e.class}: #{e.message}"
    end
    body
  end

  # Pull the four constraint kinds JSON Schema cannot express.
  def extract_model_rules(sources)
    prop_names   = Hash.new { |h, k| h[k] = [] }
    prop_values  = {}
    cardinalities = []
    role_ids     = []

    sources.each_value do |body|
      body.scan(%r{<allowed-values\b([^>]*)>(.*?)</allowed-values>}m) do |attrs, inner|
        target = attrs[/target="([^"]*)"/, 1].to_s
        id     = attrs[/id="([^"]*)"/, 1].to_s
        # allow-other="yes" means ADVISORY: the value is suggested, not enforced.
        # Conflating the two is how a real violation gets reported as a warning
        # and a legal extension gets reported as an error.
        advisory = attrs[/allow-other="([^"]*)"/, 1] == "yes"
        # `<enum\b[^>]*\svalue=` — NOT `<enum\s+value=`. Enums that arrive by
        # entity expansion carry an xmlns FIRST:
        #   <enum xmlns="http://csrc.nist.gov/ns/oscal/metaschema/1.0" value="…">
        # The tighter pattern silently dropped all 17 NIST role ids while the
        # task reported success, leaving only the 9 declared inline.
        enums    = inner.scan(/<enum\b[^>]*\svalue="([^"]*)"/).flatten.uniq

        if target.include?("role-id")
          role_ids |= enums
        elsif target.include?("/@name") && target.include?("has-oscal-namespace")
          enums.each { |e| prop_names[e] |= [ id.presence || target ] }
        elsif target.include?("/@value")
          name = target[/@name='([^']+)'/, 1] || target[/@name=\(([^)]+)\)/, 1].to_s.delete("'")
          prop_names[name] |= [ id.presence || target ] if name.present?
          prop_values[name.presence || id] = {
            "values" => enums, "advisory" => advisory, "target" => target
          }
        end
      end

      body.scan(/<has-cardinality\b([^>]*)\/>/) do |attrs|
        attrs = attrs.first
        cardinalities << {
          "id" => attrs[/id="([^"]*)"/, 1],
          "target" => attrs[/target="([^"]*)"/, 1],
          "min_occurs" => attrs[/min-occurs="([^"]*)"/, 1]&.to_i,
          "max_occurs" => attrs[/max-occurs="([^"]*)"/, 1]
        }.compact
      end
    end

    {
      "prop_names" => prop_names.transform_values(&:sort).sort.to_h,
      "prop_values" => prop_values.sort.to_h,
      "cardinalities" => cardinalities,
      "role_ids" => role_ids.sort
    }
  end
end
