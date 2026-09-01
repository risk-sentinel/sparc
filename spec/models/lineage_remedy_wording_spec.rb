# frozen_string_literal: true

require "rails_helper"

# A reconciliation remedy is rendered in the PRODUCT UI — the "Baseline not set"
# banner on every document screen, and the admin reconciliation table.
#
# Every one of the six used to BE an API call, so a compliance officer looking at
# their SAR was told to "PATCH /api/v1/sar_documents/:id { sap_document_id }".
# That is an affordance they cannot use, in a place an integrator never looks.
#
# It had already been called out once: shared/_reconciliation_banner.html.erb
# carries a comment saying the "API:" prefix and <code> styling were removed
# because "API affordances do not belong in the product UI" — but the strings
# themselves were left alone, so it shipped anyway. A comment is not a guard.
# This is the guard.
RSpec.describe "lineage remedy wording", type: :model do
  # Every model that declares lineage, found rather than listed, so a new
  # document type is covered the day it is added instead of the day someone
  # remembers to update this spec.
  let(:lineage_models) do
    Rails.root.glob("app/models/*.rb").filter_map do |path|
      klass = path.basename(".rb").to_s.camelize.safe_constantize
      klass if klass.respond_to?(:lineage_defs) && klass.lineage_defs.present?
    end
  end

  it "covers every model that declares lineage" do
    expect(lineage_models.length).to be >= 6,
      "expected the six document types with lineage; found #{lineage_models.map(&:name)}"
  end

  it "never puts an API endpoint in front of a person" do
    offenders = lineage_models.flat_map do |klass|
      klass.lineage_defs.filter_map do |definition|
        remedy = definition[:remedy].to_s
        next if remedy.empty?

        "#{klass.name}: #{remedy}" if remedy.match?(%r{/api/|\b(GET|POST|PATCH|PUT|DELETE)\b})
      end
    end

    expect(offenders).to be_empty,
      "a remedy is shown in the product UI and must read as guidance, not as a " \
      "call an integrator would make:\n  #{offenders.join("\n  ")}"
  end

  it "reads as an instruction to a person" do
    lineage_models.each do |klass|
      klass.lineage_defs.each do |definition|
        remedy = definition[:remedy].to_s
        next if remedy.empty?

        expect(remedy).to match(/\A[A-Z]/), "#{klass.name}: remedy should start with a capital"
        expect(remedy).to end_with("."), "#{klass.name}: remedy should be a sentence"
      end
    end
  end
end
