# frozen_string_literal: true

require "rails_helper"

# #942 — parsing and resolving `{{ insert: param, <id> }}`.
RSpec.describe OscalParamReference do
  # AC-20 is the issue's reproduction: odp.01's choices are composed from
  # odp.02 and odp.03 rather than being literal values.
  let(:choice) { "establish {{ insert: param, ac-20_odp.02 }}" }
  let(:labels) { { "ac-20_odp.02" => "terms and conditions", "ac-20_odp.03" => "controls asserted" } }

  describe ".ids" do
    it "extracts the referenced parameter id" do
      expect(described_class.ids(choice)).to eq([ "ac-20_odp.02" ])
    end

    it "extracts every reference in order of appearance" do
      text = "{{ insert: param, ac-20_odp.02 }} and {{ insert: param, ac-20_odp.03 }}"
      expect(described_class.ids(text)).to eq([ "ac-20_odp.02", "ac-20_odp.03" ])
    end

    it "returns nothing for a literal choice" do
      expect(described_class.ids("tunneled")).to be_empty
    end

    it "tolerates nil" do
      expect(described_class.ids(nil)).to be_empty
    end
  end

  describe ".resolve" do
    # The reference sits inside prose, so substitution has to happen in place.
    # Replacing the whole string would turn "establish terms and conditions"
    # into "terms and conditions" and lose the verb that distinguishes the
    # branches from one another.
    it "substitutes the label without discarding the surrounding prose" do
      expect(described_class.resolve(choice, labels)).to eq("establish terms and conditions")
    end

    it "resolves several references in one string" do
      text = "{{ insert: param, ac-20_odp.02 }} / {{ insert: param, ac-20_odp.03 }}"
      expect(described_class.resolve(text, labels)).to eq("terms and conditions / controls asserted")
    end

    # A gap in the catalog should look like a gap. Blanking the reference would
    # render "establish " and read as finished prose that happens to trail off.
    it "leaves a reference whose label is unknown exactly as it stands" do
      expect(described_class.resolve(choice, {})).to eq(choice)
    end

    it "leaves a blank label unresolved rather than emptying the phrase" do
      expect(described_class.resolve(choice, { "ac-20_odp.02" => "" })).to eq(choice)
    end

    it "returns a literal choice untouched" do
      expect(described_class.resolve("tunneled", labels)).to eq("tunneled")
    end
  end

  describe ".references?" do
    it "is true for a composed choice" do
      expect(described_class.references?(choice)).to be true
    end

    it "is false for a literal one" do
      expect(described_class.references?("tunneled")).to be false
    end
  end

  # The pattern had a duplicate spelling in CatalogControl. Two copies of a
  # parsing rule drift, and this one decides whether a parameter is reachable.
  it "is the rule CatalogControl uses to find its parent's params" do
    family = create(:control_family)
    parent = family.catalog_controls.create!(
      control_id: "ac-20", title: "Use of External Systems",
      params_data: [ { "id" => "ac-20_odp.02", "label" => "terms and conditions" } ]
    )
    child = family.catalog_controls.create!(
      control_id: "ac-20a", title: "establish {{ insert: param, ac-20_odp.02 }}"
    )

    expect(parent).to be_persisted
    expect(child.effective_params_list.map { |p| p["id"] }).to eq([ "ac-20_odp.02" ])
  end
end
