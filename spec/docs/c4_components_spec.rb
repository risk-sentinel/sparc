# frozen_string_literal: true

require "rails_helper"
require "yaml"

# #1206 — docs/c4/components.yml is SPARC's C4 Level 3 model, read by sparc-iac
# at the release tag it deploys. It must be in sparc-iac's descriptor schema,
# describe the release it ships in, and name code that exists.
RSpec.describe "docs/c4/components.yml" do
  let(:model) { YAML.safe_load_file(Rails.root.join("docs/c4/components.yml")) }
  let(:names) { model["components"].map { _1["name"] } }

  it "is in sparc-iac's descriptor schema, for the sparc-prod container" do
    expect(model).to include("container" => "sparc-prod", "image" => "sparc-prod", "source" => "first-party")
    expect(model.keys).to include("technology", "components", "relationships",
                                  "reviewed_by", "reviewed_date", "next_review_date")
    model["components"].each do |component|
      expect(component.keys).to include("name", "technology", "description"), component.inspect
    end
    model["relationships"].each do |rel|
      expect(rel.keys).to include("from", "to", "description", "technology"), rel.inspect
    end
  end

  it "describes the release it ships in" do
    expect(model["image_tag"]).to eq("v#{SparcConfig::VERSION}"),
      "bump image_tag with the release, then record the review"
  end

  it "names the components an assessor expects" do
    expect(names).to include("Authentication", "Authorization", "OSCAL authoring", "Evidence ingest",
                             "Background jobs", "Mail")
  end

  it "draws every relationship from a component, and to a component or an element sparc-iac draws" do
    drawn_elsewhere = %w[sparc-prod-db sparc-prod-uploads sparc-prod/admin-credentials]
    model["relationships"].each do |rel|
      expect(names).to include(rel["from"]), rel.inspect
      next if names.include?(rel["to"]) || drawn_elsewhere.include?(rel["to"])

      expect(rel["to_technology"]).to be_present, "#{rel['to']} is outside SPARC: say what it is"
    end
    expect(model["relationships"].map { _1["to"] }).to include("sparc-prod-db")
  end

  it "names code that exists" do
    model["components"].each do |component|
      Array(component["code"]).each do |path|
        expect(Rails.root.join(path)).to exist, "#{component['name']}: #{path} has moved or gone"
      end
    end
  end
end
