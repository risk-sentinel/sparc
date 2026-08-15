# frozen_string_literal: true

# #845 — give a spec the whole reference leveraged authorization estate.
#
# Specs that need a *real* authorization — two boundaries, two organizations,
# a published profile, an SSP with statements, a SAP, a SAR with findings and
# risks, POA&Ms, evidence, and live inheritance links between the two sides —
# get it from one call instead of assembling twenty factories and hoping the
# relationships they invent match the ones the product actually builds.
#
# The catalog is SYNTHESISED here rather than read from the database, even
# though a locally seeded database usually has the real Rev 5 catalog sitting
# in it. Reading it would make every such spec depend on ambient state — the
# exact trap ControlCatalogHelpers documents — and would mean a spec passing
# on a developer's machine and failing on a fresh checkout. The synthetic
# catalog carries the same control identifiers the lean tier curates, so the
# estate is the same shape everywhere it is built.
module ReferenceEstateHelper
  # Builds and returns a ReferenceEstateBuilder::Result.
  #
  # Memoised per example: the estate is expensive enough that a spec touching
  # it twice should not pay twice, and every call in one example must describe
  # the same estate anyway.
  def reference_estate(tier = :lean)
    @reference_estates ||= {}
    @reference_estates[tier.to_sym] ||=
      ReferenceEstate.load!(tier, catalog: reference_estate_catalog, verbose: false)
  end

  # The two sides, named the way the domain names them: the leveraged boundary
  # PROVIDES, the leveraging boundary CONSUMES.
  def reference_provider(tier = :lean)  = reference_estate(tier).leveraged
  def reference_consumer(tier = :lean)  = reference_estate(tier).leveraging

  # A catalog covering exactly the lean tier's controls. Statements matter:
  # #955 exists because a control with no `statement` in guidance_data produces
  # an SSP control with nowhere to write an implementation, so a fixture that
  # omitted them would quietly exercise a different code path than production.
  def reference_estate_catalog
    @reference_estate_catalog ||= begin
      catalog = FactoryBot.create(:control_catalog, name: "Reference Estate Rev 5 Catalog")
      families = {}

      ReferenceEstateBuilder::LEAN_CONTROL_IDS.each do |control_id|
        code = control_id.split("-").first.upcase
        family = families[code] ||=
          FactoryBot.create(:control_family, control_catalog: catalog, code: code)

        FactoryBot.create(
          :catalog_control,
          control_family: family,
          control_id:     control_id,
          title:          "Reference control #{control_id.upcase}",
          guidance_data:  { "statement" => "Requirement text for #{control_id.upcase}." }
        )
      end

      catalog
    end
  end
end

RSpec.configure do |config|
  config.include ReferenceEstateHelper
end
