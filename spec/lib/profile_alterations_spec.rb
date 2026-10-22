# frozen_string_literal: true

require "rails_helper"

# #1252 — OSCAL `alters`: removes by each criterion, adds by each position.
# Invented control; every expectation is read off the control it builds.
RSpec.describe ProfileAlterations do
  let(:control) do
    {
      "id" => "zz-1",
      "params" => [ { "id" => "zz-01_odp.01", "label" => "frequency" } ],
      "props" => [ { "name" => "label", "value" => "ZZ-1" }, { "name" => "status", "ns" => "https://example.org/ns", "value" => "x" } ],
      "links" => [ { "href" => "#r1", "rel" => "reference" } ],
      "parts" => [
        { "id" => "zz-1_smt", "name" => "statement", "parts" => [
          { "id" => "zz-1_smt.a", "name" => "item", "class" => "keep", "prose" => "Do a." },
          { "id" => "zz-1_smt.b", "name" => "item", "class" => "drop", "prose" => "Do b." }
        ] },
        { "id" => "zz-1_gdn", "name" => "guidance", "prose" => "Guidance." }
      ]
    }
  end

  def apply(*alters, **opts) = described_class.new(alters, **opts).apply!(control.deep_dup)
  def part_ids(node) = Array(node["parts"]).flat_map { |p| [ p["id"] ] + part_ids(p) }

  describe "removes" do
    it "by-id removes that part and its children, at any depth" do
      result = apply({ "removes" => [ { "by-id" => "zz-1_smt.b" } ] })
      expect(part_ids(result)).to eq(part_ids(control) - %w[zz-1_smt.b])
    end

    it "by-name removes every item with that name" do
      result = apply({ "removes" => [ { "by-name" => "guidance" } ] })
      expect(part_ids(result)).not_to include("zz-1_gdn")
    end

    it "by-class removes only what carries that class" do
      result = apply({ "removes" => [ { "by-class" => "drop" } ] })
      expect(part_ids(result)).to include("zz-1_smt.a")
      expect(part_ids(result)).not_to include("zz-1_smt.b")
    end

    it "by-ns removes props in that namespace and leaves the rest" do
      result = apply({ "removes" => [ { "by-ns" => "https://example.org/ns" } ] })
      expect(result["props"].map { |p| p["name"] }).to eq([ "label" ])
    end

    it "by-item-name limits a remove to one kind" do
      result = apply({ "removes" => [ { "by-item-name" => "link" } ] })
      expect(result).not_to have_key("links")
      expect(result["params"]).to eq(control["params"])
    end

    it "requires every criterion given to match" do
      result = apply({ "removes" => [ { "by-name" => "item", "by-class" => "drop" } ] })
      expect(part_ids(result)).to include("zz-1_smt.a")
      expect(part_ids(result)).not_to include("zz-1_smt.b")
    end

    it "a remove with no criteria removes nothing" do
      expect(apply({ "removes" => [ {} ] })).to eq(control)
    end
  end

  describe "adds" do
    let(:new_part) { { "id" => "zz-1_smt.c", "name" => "item", "prose" => "Do c." } }

    it "after by-id places the part immediately after the target" do
      result = apply({ "adds" => [ { "position" => "after", "by-id" => "zz-1_smt.a", "parts" => [ new_part ] } ] })
      expect(result["parts"][0]["parts"].map { |p| p["id"] }).to eq(%w[zz-1_smt.a zz-1_smt.c zz-1_smt.b])
    end

    it "before by-id places the part immediately before the target" do
      result = apply({ "adds" => [ { "position" => "before", "by-id" => "zz-1_smt.a", "parts" => [ new_part ] } ] })
      expect(result["parts"][0]["parts"].map { |p| p["id"] }).to eq(%w[zz-1_smt.c zz-1_smt.a zz-1_smt.b])
    end

    it "starting and ending by-id place the part first and last among the target's children" do
      first = apply({ "adds" => [ { "position" => "starting", "by-id" => "zz-1_smt", "parts" => [ new_part ] } ] })
      last  = apply({ "adds" => [ { "position" => "ending", "by-id" => "zz-1_smt", "parts" => [ new_part ] } ] })
      expect(first["parts"][0]["parts"].first["id"]).to eq("zz-1_smt.c")
      expect(last["parts"][0]["parts"].last["id"]).to eq("zz-1_smt.c")
    end

    it "with no by-id adds to the control itself, ending by default" do
      result = apply({ "adds" => [ { "parts" => [ new_part ] } ] })
      expect(result["parts"].last["id"]).to eq("zz-1_smt.c")
    end

    it "places nothing for a by-id the control does not have, and reports it" do
      alterations = described_class.new([ { "adds" => [ { "position" => "after", "by-id" => "zz-1_nope", "parts" => [ new_part ] } ] } ])
      result = alterations.apply!(control.deep_dup)
      expect(part_ids(result)).to eq(part_ids(control))
      expect(alterations.unplaced).to eq(%w[zz-1_nope])
    end

    it "removes before it adds, so an alter can replace a part" do
      result = apply({ "removes" => [ { "by-id" => "zz-1_smt.b" } ],
                       "adds" => [ { "position" => "ending", "by-id" => "zz-1_smt", "parts" => [ new_part ] } ] })
      expect(result["parts"][0]["parts"].map { |p| p["id"] }).to eq(%w[zz-1_smt.a zz-1_smt.c])
    end

    it "an added part the same alter's remove would match survives: removes run first" do
      result = apply({ "removes" => [ { "by-class" => "drop" } ],
                       "adds" => [ { "position" => "ending", "by-id" => "zz-1_smt", "parts" => [ new_part.merge("class" => "drop") ] } ] })
      expect(result["parts"][0]["parts"].map { |p| p["id"] }).to eq(%w[zz-1_smt.a zz-1_smt.c])
    end

    it "resolves an added part's prose through the given resolver" do
      add = { "adds" => [ { "parts" => [ new_part.merge("prose" => "Every {{ insert: param, zz-01_odp.01 }}.") ] } ] }
      result = apply(add, resolve: ->(text) { text.gsub(/\{\{.*?\}\}/, "quarter") })
      expect(result["parts"].last["prose"]).to eq("Every quarter.")
    end

    it "does not add props: those keep their own home" do
      result = apply({ "adds" => [ { "props" => [ { "name" => "priority", "value" => "P1" } ] } ] })
      expect(result["props"]).to eq(control["props"])
    end
  end
end
