require "rails_helper"

RSpec.describe OscalExtensibilityParams do
  let(:host_class) do
    Class.new do
      include OscalExtensibilityParams
      public :compact_props, :compact_links, :compact_origins
    end
  end
  let(:host) { host_class.new }

  describe "#compact_props" do
    it "drops rows missing name or value" do
      result = host.compact_props([
        { "name" => "kept",     "value" => "yes" },
        { "name" => "no_value", "value" => "" },
        { "name" => "",         "value" => "no_name" },
        { "name" => "",         "value" => "" }
      ])
      expect(result).to eq([ { "name" => "kept", "value" => "yes" } ])
    end

    it "preserves optional class field when present" do
      result = host.compact_props([ { "name" => "n", "value" => "v", "class" => "ns" } ])
      expect(result).to eq([ { "name" => "n", "value" => "v", "class" => "ns" } ])
    end
  end

  describe "#compact_links" do
    it "drops rows missing href" do
      result = host.compact_links([
        { "href" => "https://kept.gov" },
        { "href" => "", "rel" => "reference" }
      ])
      expect(result).to eq([ { "href" => "https://kept.gov" } ])
    end

    it "converts media_type to OSCAL media-type" do
      result = host.compact_links([
        { "href" => "https://x.gov", "media_type" => "application/pdf" }
      ])
      expect(result.first["media-type"]).to eq("application/pdf")
      expect(result.first).not_to have_key("media_type")
    end
  end

  describe "#compact_origins" do
    it "wraps each row as { actors: [actor-shape] } with hyphen keys" do
      result = host.compact_origins([
        { "actor_type" => "party", "actor_uuid" => "uuid-1", "role_id" => "assessor" }
      ])
      expect(result).to eq([
        { "actors" => [ { "type" => "party", "actor-uuid" => "uuid-1", "role-id" => "assessor" } ] }
      ])
    end

    it "drops rows missing actor_uuid" do
      result = host.compact_origins([
        { "actor_type" => "party", "actor_uuid" => "" },
        { "actor_type" => "party", "actor_uuid" => "uuid-2" }
      ])
      expect(result.size).to eq(1)
      expect(result.first.dig("actors", 0, "actor-uuid")).to eq("uuid-2")
    end

    it "defaults actor type to 'party' when omitted" do
      result = host.compact_origins([ { "actor_uuid" => "uuid-x" } ])
      expect(result.first.dig("actors", 0, "type")).to eq("party")
    end

    it "omits role-id when blank" do
      result = host.compact_origins([
        { "actor_type" => "party", "actor_uuid" => "uuid-x", "role_id" => "" }
      ])
      expect(result.first.dig("actors", 0)).not_to have_key("role-id")
    end
  end
end
