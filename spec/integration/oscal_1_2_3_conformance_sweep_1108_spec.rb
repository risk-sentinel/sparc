# frozen_string_literal: true

require "rails_helper"

# #1108 — the conformance sweep against OSCAL 1.2.3, which SPARC adopted as
# DEFAULT_VERSION (#1105, 7efee101). Every OSCAL document SPARC commits, from
# each of its export models, is checked against:
#
#   * the tracked 1.2.3 JSON schema (lib/oscal_schemas/, proved to be 1.2.3
#     first: the 1.2.2 bundle is gitignored and absent in CI, so a spec may not
#     read it), and
#   * the Metaschema conformance vocabularies of BOTH 1.2.2 and 1.2.3
#     (lib/oscal_conformance/, tracked), because `oscal_version` is
#     per-document and a document that keeps 1.2.2 must keep conforming.
#
# Measured diff 1.2.2 -> 1.2.3 (docs/dev/1108_oscal_1_2_3_sweep.md): no
# enumeration changed its enforcement form, and the one vocabulary change is
# the catalog `status` prop, from an enforced ["withdrawn", "Withdrawn"] to an
# advisory list. The last example pins that, so a dataset regenerated with a
# different answer fails here rather than silently changing what conforms.
RSpec.describe "OSCAL 1.2.3 conformance sweep (#1108)" do
  root = Rails.root

  documents = (
    Dir[root.join("spec/fixtures/files/end_to_end/*.json")] +
    Dir[root.join("samples/nist-traditional-demo/*.json")] +
    [ root.join("samples/ato-package-demo/cdef-example.json").to_s ] +
    Dir[root.join("docs/api/samples/custom-controls-*.json")] +
    Dir[root.join("docs/compliance/oscal/cdefs/*.json")]
  ).sort

  schema_model = {
    "catalog" => :catalog, "profile" => :profile, "component-definition" => :component_definition,
    "system-security-plan" => :ssp, "assessment-plan" => :assessment_plan,
    "assessment-results" => :assessment_results, "plan-of-action-and-milestones" => :poam
  }

  it "sweeps a document of every model SPARC exports" do
    models = documents.map { |path| JSON.parse(File.read(path)).keys.first }.uniq
    expect(models).to include(*schema_model.keys)
  end

  it "validates against the tracked schema set, which is 1.2.3" do
    tracked = JSON.parse(root.join("lib/oscal_schemas/oscal_ssp_schema.json").read)
    expect(tracked["$id"][%r{/oscal/([\d.]+)/}, 1]).to eq("1.2.3")
    expect(OscalSchema::DEFAULT_VERSION).to eq("1.2.3")
  end

  documents.each do |path|
    relative = Pathname(path).relative_path_from(root).to_s

    describe relative do
      let(:data) { JSON.parse(File.read(path)) }
      let(:model) { data.keys.first }

      it "is valid against the 1.2.3 schema" do
        result = OscalSchemaValidationService.validate(schema_model.fetch(model), data)
        expect(result.errors).to be_empty
      end

      %w[1.2.2 1.2.3].each do |version|
        it "has no #{version} conformance violation" do
          doc = data.deep_dup
          doc[model]["metadata"]["oscal-version"] = version
          result = OscalConformanceService.new(doc, model: model).validate

          expect(result.oscal_version).to eq(version)
          expect(result.violations.map(&:message)).to be_empty
        end
      end
    end
  end

  it "differs from 1.2.2 only in the catalog status vocabulary" do
    older = JSON.parse(root.join("lib/oscal_conformance/1.2.2/conformance.json").read)
    newer = JSON.parse(root.join("lib/oscal_conformance/1.2.3/conformance.json").read)

    changed = newer["models"].keys.flat_map do |model|
      (newer["models"][model].keys | older["models"].fetch(model, {}).keys).flat_map do |section|
        a = older.dig("models", model, section) || {}
        b = newer.dig("models", model, section) || {}
        next [] unless a.is_a?(Hash) && b.is_a?(Hash)

        (a.keys | b.keys).reject { |k| a[k] == b[k] }.map { |k| "#{model}/#{section}/#{k}" }
      end
    end
    expect(changed).to eq([ "catalog/prop_values/status" ])
    expect(older.dig("models", "catalog", "prop_values", "status", "advisory")).to be(false)
    expect(newer.dig("models", "catalog", "prop_values", "status", "advisory")).to be(true)
  end
end
