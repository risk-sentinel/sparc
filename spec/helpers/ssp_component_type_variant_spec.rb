# frozen_string_literal: true

require "rails_helper"

# #1088 — the OSCAL component-type vocabulary, mapped centrally.
#
# The view carried `comp.component_type == 'this-system' ? 'purple' : 'info'`,
# which collapsed NINE OSCAL types into two colours. `validation` — the type
# #998 added so a component can carry a FIPS certificate — rendered identically
# to `software` on the screen that introduced it.
RSpec.describe ApplicationHelper, type: :helper do
  describe "#ssp_component_type_variant" do
    it "covers every type the model allows" do
      SspComponent::COMPONENT_TYPES.each do |type|
        expect(ApplicationHelper::SSP_COMPONENT_TYPE_VARIANTS).to have_key(type),
          "#{type} has no variant, so it would silently fall back to neutral"
      end
    end

    # `this-system` is the component that IS the system rather than a part of it.
    # That is the distinction a reader most needs on this tile.
    it "keeps this-system distinct from everything else" do
      others = SspComponent::COMPONENT_TYPES.reject { |t| t == "this-system" }
                                            .map { |t| helper.ssp_component_type_variant(t) }

      expect(helper.ssp_component_type_variant("this-system")).to eq("purple")
      expect(others).not_to include("purple")
    end

    it "no longer renders validation as though it were software" do
      expect(helper.ssp_component_type_variant("validation"))
        .not_to eq(helper.ssp_component_type_variant("software"))
    end

    # Every variant must be one the theme actually defines, or the badge renders
    # unstyled and the AA-verified pairing is lost.
    it "only uses variants the theme defines" do
      css = Rails.root.join("app/assets/stylesheets/sparc-theme.css").read
      ApplicationHelper::SSP_COMPONENT_TYPE_VARIANTS.each_value do |variant|
        expect(css).to include(".sparc-status--#{variant}"),
          "sparc-status--#{variant} is not defined in the theme"
      end
    end

    it "falls back to neutral for a type the model does not know" do
      expect(helper.ssp_component_type_variant("nonsense")).to eq("neutral")
      expect(helper.ssp_component_type_variant(nil)).to eq("neutral")
    end
  end
end
