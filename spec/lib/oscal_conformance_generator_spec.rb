# frozen_string_literal: true

require "rails_helper"
require "rake"

# #1106 — the conformance dataset GENERATOR, as distinct from the data it emits.
#
# `spec/lib/oscal_conformance_dataset_spec.rb` asserts the committed artifact.
# That is necessary and not sufficient: break the extraction tomorrow and those
# examples stay green, because the JSON on disk is still correct. The regression
# would surface only at the next `bundle_conformance` run — the moment nobody is
# looking at it closely.
#
# ── Why these specs are shaped this way ────────────────────────────────────
#
# `extract_model_rules` is a PURE function over a Hash of metaschema bodies, so
# it is exercised directly against small inline fixtures: no network, no
# stubbing, no rake invocation. That matters. A spec that shelled out to the real
# task with a mocked fetcher would execute every line — perfect coverage — and
# assert almost nothing, which is how a generator bug hides behind a green suite.
#
# Both examples below pin a bug that ACTUALLY SHIPPED in this file and was caught
# by reading output, not by a test:
#
#   1. `<enum\s+value=` missed every entity-supplied term, because those carry an
#      xmlns first. The task reported SUCCESS with 9 role ids instead of 26.
#   2. Prop names and part names were folded together — both are constrained by
#      targets ending in `/@name` — so `statement` and `guidance`, which are PART
#      names, were recorded as catalog PROP names. A conformance check built on
#      that would have accepted a prop named `statement` as NIST-defined.
RSpec.describe "OSCAL conformance generator" do
  # Rake task bodies define their helpers as Object methods once loaded.
  #
  # `Rake.application` is GLOBAL. An earlier version of this file called
  # `Rake::Task.clear` and installed a fresh application without restoring the
  # old one, which wiped every task the rest of the suite relies on — specs
  # doing `Rake::Task["sparc:bootstrap_admin"]` then died with "Don't know how to
  # build task". It passed in isolation and broke CI, which is the signature of
  # global state mutated in a before(:all).
  #
  # A private application is installed for the load and the original put back.
  before(:all) do
    @original_rake_application = Rake.application
    Rake.application = Rake::Application.new
    load Rails.root.join("lib/tasks/oscal_schemas.rake")
    load Rails.root.join("lib/tasks/oscal_conformance.rake")
  end

  after(:all) do
    Rake.application = @original_rake_application
  end

  let(:subject_obj) { Object.new }

  def extract(xml)
    subject_obj.send(:extract_model_rules, { "fixture.xml" => xml })
  end

  describe "prop names versus part names" do
    # Both targets end in /@name. Telling them apart is the whole point.
    let(:xml) do
      <<~XML
        <METASCHEMA>
          <allowed-values id="prop-names" target="prop[has-oscal-namespace('http://csrc.nist.gov/ns/oscal')]/@name">
            <enum value="label">A human label.</enum>
            <enum value="sort-id">An ordering key.</enum>
          </allowed-values>
          <allowed-values id="part-names" target="part[has-oscal-namespace('http://csrc.nist.gov/ns/oscal')]/@name">
            <enum value="statement">The control statement.</enum>
            <enum value="guidance">Supplemental guidance.</enum>
          </allowed-values>
        </METASCHEMA>
      XML
    end

    it "records prop names as props" do
      expect(extract(xml)["prop_names"].keys).to contain_exactly("label", "sort-id")
    end

    it "records part names as parts, NOT props" do
      rules = extract(xml)

      expect(rules["part_names"].keys).to contain_exactly("statement", "guidance")
      expect(rules["prop_names"]).not_to include("statement"), <<~MSG
        A PART name was recorded as a PROP name. A conformance check built on this
        would accept a prop named "statement" as NIST-defined, which is the defect
        this separation exists to prevent.
      MSG
    end

    # `part[…]/prop[…]/@name` is a PROP constraint: the element is the LAST path
    # step before /@name, not the first.
    it "reads the last path step, so a nested prop target is a prop" do
      nested = <<~XML
        <METASCHEMA>
          <allowed-values id="nested" target="part[@name='assessment']/prop[has-oscal-namespace('http://csrc.nist.gov/ns/oscal')]/@name">
            <enum value="method">An assessment method.</enum>
          </allowed-values>
        </METASCHEMA>
      XML

      rules = extract(nested)
      expect(rules["prop_names"]).to include("method")
      expect(rules["part_names"]).not_to include("method")
    end
  end

  describe "enum values that carry attributes before value=" do
    # This is the exact shape NIST ships inside shared-constraints/*.ent, and the
    # reason the task once reported success with 9 role ids instead of 26.
    let(:xml) do
      <<~XML
        <METASCHEMA>
          <allowed-values id="roles" target="responsible-role/@role-id" allow-other="yes">
            <enum value="system-owner">Declared inline.</enum>
            <enum xmlns="http://csrc.nist.gov/ns/oscal/metaschema/1.0" value="information-system-security-officer">Via an entity include.</enum>
          </allowed-values>
        </METASCHEMA>
      XML
    end

    it "captures an enum whose value= is not the first attribute" do
      expect(extract(xml)["role_ids"]).to contain_exactly(
        "system-owner", "information-system-security-officer"
      )
    end
  end

  describe "enforced versus advisory vocabularies" do
    let(:xml) do
      <<~XML
        <METASCHEMA>
          <allowed-values id="enforced" target="prop[@name='control-origination']/@value">
            <enum value="inherited">Inherited.</enum>
          </allowed-values>
          <allowed-values id="advisory" target="prop[@name='state']/@value" allow-other="yes">
            <enum value="operational">Operational.</enum>
          </allowed-values>
        </METASCHEMA>
      XML
    end

    # Conflating these is how a real violation gets reported as a warning and a
    # legal extension gets reported as an error.
    it "marks allow-other='yes' advisory and its absence enforced" do
      values = extract(xml)["prop_values"]

      expect(values["control-origination"]["advisory"]).to be(false)
      expect(values["state"]["advisory"]).to be(true)
    end
  end

  describe "cardinality constraints" do
    it "captures min-occurs, which JSON Schema does not express for props" do
      xml = <<~XML
        <METASCHEMA>
          <has-cardinality id="method-required" target="prop[@name='method']" min-occurs="1"/>
        </METASCHEMA>
      XML

      card = extract(xml)["cardinalities"].first
      expect(card["id"]).to eq("method-required")
      expect(card["min_occurs"]).to eq(1)
    end
  end

  describe "entity expansion" do
    # Exercised with a PRE-SEEDED cache: the method only fetches on a miss, so
    # this covers the substitution without touching the network.
    it "substitutes an entity's content in place of its reference" do
      # The cache key keeps the path EXACTLY as the <!ENTITY> declares it — the
      # "./" is stripped only when building the URL, not for the lookup. Getting
      # that wrong here produced a cache miss, a network attempt, and a body that
      # came back unexpanded.
      cache = { [ "1.2.2", "./shared-constraints/roles.ent" ] => '<enum value="privacy-poc">POC.</enum>' }
      body  = <<~XML
        <!ENTITY roles SYSTEM "./shared-constraints/roles.ent">
        <allowed-values target="responsible-role/@role-id">&roles;</allowed-values>
      XML

      expanded = subject_obj.send(:expand_entities, "1.2.2", body, cache)

      expect(expanded).to include('<enum value="privacy-poc">')
      expect(expanded).not_to include("&roles;"), "the entity reference survived unexpanded"
    end
  end
end
