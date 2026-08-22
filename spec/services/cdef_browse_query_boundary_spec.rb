# frozen_string_literal: true

require "rails_helper"

# #951 — "the CDEFs this boundary is using".
#
# The sidebar has linked to the CDEF index with `?authorization_boundary_id=`
# since #796 and NOTHING read it. `CdefBrowseQuery::FACETS` is
# partition/capability/checks and the default scope is every CdefDocument, so
# every boundary's "CDEFs" leaf listed the whole instance. Measured against the
# running instance before the fix: unfiltered 234, with the parameter 234, with
# a bogus `cdef_type` 0 — the last being the control that shows the index does
# narrow on a parameter it supports.
#
# Both directions matter here. A filter that returned nothing would also have
# "narrowed", so each example below pins what is INCLUDED as well as what is
# excluded.
RSpec.describe CdefBrowseQuery, "boundary scoping" do
  let(:boundary) { create(:authorization_boundary) }
  let(:other_boundary) { create(:authorization_boundary) }

  def documents_for(boundary_id)
    described_class.new({ authorization_boundary_id: boundary_id }).documents
  end

  describe "a CDEF selected for one of the boundary's environments" do
    it "is included, and another boundary's is not" do
      env = boundary.boundaries.create!(name: "Default", environment: "production")
      mine = create(:cdef_document)
      env.boundary_cdef_documents.create!(cdef_document: mine)

      other_env = other_boundary.boundaries.create!(name: "Default", environment: "production")
      theirs = create(:cdef_document)
      other_env.boundary_cdef_documents.create!(cdef_document: theirs)

      expect(documents_for(boundary.id)).to include(mine)
      expect(documents_for(boundary.id)).not_to include(theirs)
    end
  end

  describe "a CDEF consumed by the boundary's SSP" do
    it "is included even with no environment link" do
      cdef = create(:cdef_document)
      ssp = create(:ssp_document, authorization_boundary: boundary)
      ssp.ssp_components.create!(uuid: SecureRandom.uuid, title: "Component",
                                 description: "d", component_type: "software",
                                 cdef_document: cdef)

      # The two selections are populated together by the ATO wizard, but
      # SspWizardService can be called on its own, which writes the component
      # and no BoundaryCdefDocument. Missing it would tell someone they are not
      # using a component definition their own SSP is built on.
      expect(boundary.boundaries).to be_empty
      expect(documents_for(boundary.id)).to include(cdef)
    end
  end

  describe "a CDEF the boundary does not use at all" do
    it "is excluded" do
      unrelated = create(:cdef_document)

      expect(documents_for(boundary.id)).not_to include(unrelated)
    end
  end

  describe "without the parameter" do
    it "returns every CDEF, so Implementation > Component Definitions is unscoped" do
      env = boundary.boundaries.create!(name: "Default", environment: "production")
      used = create(:cdef_document)
      env.boundary_cdef_documents.create!(cdef_document: used)
      unused = create(:cdef_document)

      all = described_class.new({}).documents

      expect(all).to include(used, unused)
    end
  end

  describe "an unknown boundary" do
    it "returns nothing rather than everything" do
      create(:cdef_document)

      expect(documents_for(0)).to be_empty
    end
  end

  it "still intersects the free-text search rather than replacing it" do
    env = boundary.boundaries.create!(name: "Default", environment: "production")
    wanted = create(:cdef_document, name: "Boundary IAM component")
    other  = create(:cdef_document, name: "Boundary Logging component")
    env.boundary_cdef_documents.create!(cdef_document: wanted)
    env.boundary_cdef_documents.create!(cdef_document: other)

    result = described_class.new(
      { authorization_boundary_id: boundary.id, q: "IAM" }
    ).documents

    expect(result).to include(wanted)
    expect(result).not_to include(other)
  end
end
