# frozen_string_literal: true

require "rails_helper"

# #998 — `validation` was an allowed component type and nothing could say what
# a validation component validates. OSCAL models third-party product validation
# as a component PAIR: the product, and a `validation` component carrying
# `validation-type` / `validation-reference` props and a `validation-details`
# link to the authoritative record, joined by a link with `rel="validation"`
# from the product to the validation.
#
# The pairing is the point. A validation component pointing at nothing is
# another partial, which is what an enum value with no supporting fields
# already was.
RSpec.describe "Validation component modeling (#998)" do
  let(:boundary) { create(:authorization_boundary) }
  let(:ssp) { create(:ssp_document, authorization_boundary: boundary) }

  # The SSP schema requires at least one implemented requirement, and #911's
  # reconciliation gate refuses a control that exists in no loaded catalog — so
  # a real catalog control is a precondition of exporting at all. Present so
  # the schema assertions below exercise the export rather than this setup.
  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }
  let!(:catalog_control) do
    create(:catalog_control, control_family: family, control_id: "ac-1",
                             title: "Policy and Procedures")
  end
  let!(:ssp_control) do
    create(:ssp_control, ssp_document: ssp, control_id: "ac-1", title: "Policy and Procedures")
  end

  let!(:product) do
    ssp.ssp_components.create!(uuid: SecureRandom.uuid, component_type: "software",
                               title: "Acme Crypto Module", description: "The validated module.")
  end

  let!(:validation) do
    ssp.ssp_components.create!(
      uuid: SecureRandom.uuid, component_type: "validation",
      title: "FIPS 140-2 certificate #4282",
      description: "NIST CMVP validation of the Acme Crypto Module.",
      validation_type: "fips-140-2",
      validation_reference: "4282",
      validation_details_href: "https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4282",
      validated_component: product
    )
  end

  describe "the model" do
    it "refuses a validation claim on a component that is not a validation" do
      product.validation_reference = "4282"

      expect(product).not_to be_valid
      expect(product.errors[:component_type].join).to include("validation")
    end

    it "refuses a component that validates itself" do
      validation.validates_component_id = validation.id
      expect(validation).not_to be_valid
    end

    it "refuses a target in another system security plan" do
      other = create(:ssp_document, authorization_boundary: boundary)
                .ssp_components.create!(uuid: SecureRandom.uuid, component_type: "software",
                                        title: "Elsewhere", description: "Another SSP.")
      validation.validates_component_id = other.id

      expect(validation).not_to be_valid
    end

    # Deleting a product must not silently take the certificate record with it:
    # a validation left pointing at nothing is a visible loose end, a deleted
    # one is not.
    it "keeps the validation when its product is deleted" do
      product.destroy!

      expect(validation.reload).to be_persisted
      expect(validation.validates_component_id).to be_nil
    end
  end

  describe "the export" do
    let(:components) do
      JSON.parse(OscalSspExportService.new(ssp).export_unvalidated)
          .dig("system-security-plan", "system-implementation", "components")
    end
    let(:exported_validation) { components.find { |c| c["uuid"] == validation.uuid } }
    let(:exported_product)    { components.find { |c| c["uuid"] == product.uuid } }

    it "carries the certificate as props on the validation component" do
      props = exported_validation["props"].to_h { |p| [ p["name"], p["value"] ] }

      expect(props["validation-type"]).to eq("fips-140-2")
      expect(props["validation-reference"]).to eq("4282")
    end

    it "links the validation component to the authoritative record" do
      detail = exported_validation["links"].find { |l| l["rel"] == "validation-details" }

      expect(detail["href"]).to include("certificate/4282")
    end

    # The half that makes it a pair rather than two unrelated components.
    it "links the PRODUCT to its validation" do
      link = exported_product["links"].find { |l| l["rel"] == "validation" }

      expect(link["href"]).to eq("##{validation.uuid}")
    end

    it "adds to the component's own props and links rather than replacing them" do
      product.update!(props_data: [ { "name" => "asset-type", "value" => "appliance" } ])
      props = exported_product["props"].to_h { |p| [ p["name"], p["value"] ] }

      expect(props["asset-type"]).to eq("appliance")
      expect(exported_product["links"].map { |l| l["rel"] }).to include("validation")
    end

    it "remains schema-valid through the validated path, not export_unvalidated" do
      expect { OscalSspExportService.new(ssp).export }.not_to raise_error
    end
  end

  describe "the round trip" do
    it "restores both the certificate and the pairing on import" do
      json = OscalSspExportService.new(ssp).export
      file = Tempfile.new([ "ssp", ".json" ])
      file.write(json)
      file.rewind

      imported = create(:ssp_document, authorization_boundary: boundary, name: "reimported")
      SspJsonParserService.new(imported, file.path).parse

      restored = imported.ssp_components.find_by(uuid: validation.uuid)
      expect(restored.validation_type).to eq("fips-140-2")
      expect(restored.validation_reference).to eq("4282")
      expect(restored.validation_details_href).to include("certificate/4282")

      # The pairing has to survive too, or the certificate is about nothing.
      expect(restored.validated_component.uuid).to eq(product.uuid)
    ensure
      file&.close
      file&.unlink
    end
  end
end

# The CDEF half of #998, and the reason the decision was "SSP first".
#
# OscalComponentDefinitionExportService emits `"components" => [ build_component ]`
# — exactly ONE component, built from the cdef_documents.component_* columns —
# so a CDEF cannot carry the product/validation PAIR at all. What it CAN do,
# and previously could not, is carry its own component-level props and links:
# they were emitted on implemented-requirements and statements, and on the
# component they were dropped outright, so an imported claim did not survive
# the round trip.
RSpec.describe "CDEF component props and links (#998)" do
  let(:cdef) do
    create(:cdef_document,
      component_type: "validation",
      component_title: "FIPS 140-2 certificate #4282",
      component_props_data: [
        { "name" => "validation-type", "value" => "fips-140-2" },
        { "name" => "validation-reference", "value" => "4282" }
      ],
      component_links_data: [
        { "href" => "https://csrc.nist.gov/…/certificate/4282", "rel" => "validation-details" }
      ])
  end

  let!(:control) do
    create(:cdef_control, cdef_document: cdef, control_id: "ac-1", title: "Policy and Procedures")
  end

  let(:component) do
    JSON.parse(OscalComponentDefinitionExportService.new(cdef).export_unvalidated)
        .dig("component-definition", "components", 0)
  end

  it "emits props on the component, matching the SSP exporter's behaviour" do
    expect(component["props"].to_h { |p| [ p["name"], p["value"] ] })
      .to include("validation-type" => "fips-140-2", "validation-reference" => "4282")
  end

  it "emits links on the component" do
    expect(component["links"].first["rel"]).to eq("validation-details")
  end

  it "omits the keys entirely when there is nothing to say, rather than emitting empties" do
    bare = create(:cdef_document)
    create(:cdef_control, cdef_document: bare, control_id: "ac-1", title: "Policy")
    emitted = JSON.parse(OscalComponentDefinitionExportService.new(bare).export_unvalidated)
                  .dig("component-definition", "components", 0)

    expect(emitted).not_to have_key("props")
    expect(emitted).not_to have_key("links")
  end

  it "keeps control-implementations after the added keys, as OSCAL orders them" do
    expect(component.keys).to eq(%w[uuid type title description props links control-implementations])
  end
end
