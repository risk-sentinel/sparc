# frozen_string_literal: true

require "rails_helper"

# #980 — the third scope tier. Owner CDEF screen review: "CDEF's are Boundary,
# Organization, Instance availability but only Boundary and Organizational
# exist."
#
# The encoding needed no new column — it was always expressible and simply never
# reachable:
#
#   boundary      globally_available: false + boundary_cdef_documents rows
#   organization  globally_available: true  + organization_id: <the org>
#   instance      globally_available: true  + organization_id: NULL
#
# The trap is the READER. `globally_available_in(org)` matched
# `organization_id: org.id` exactly, so a NULL-organization CDEF was visible to
# NOBODY rather than to everybody — the precise inversion of what the tier means.
RSpec.describe "CdefScopeService instance-wide tier" do
  let(:org)       { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:cdef)      { create(:cdef_document, organization: org, globally_available: true) }

  describe "applying the tier" do
    it "clears the owning organization" do
      CdefScopeService.apply(cdef, scope: "instance")

      expect(cdef.reload.globally_available).to be(true)
      expect(cdef.organization_id).to be_nil
      expect(cdef.scope_tier).to eq(:instance)
    end

    it "unlinks a boundary the CDEF was previously scoped to" do
      boundary = create(:authorization_boundary)
      sub = create(:boundary, authorization_boundary: boundary)
      CdefScopeService.apply(cdef, scope: "boundary", authorization_boundary_id: boundary.id)
      expect(BoundaryCdefDocument.where(cdef_document_id: cdef.id, boundary_id: sub.id)).to exist

      CdefScopeService.apply(cdef, scope: "instance")

      expect(BoundaryCdefDocument.where(cdef_document_id: cdef.id, boundary_id: sub.id)).not_to exist
      expect(cdef.reload.scope_tier).to eq(:instance)
    end

    it "is reversible back to organization-wide" do
      CdefScopeService.apply(cdef, scope: "instance")
      CdefScopeService.apply(cdef, scope: "global", organization_id: org.id)

      expect(cdef.reload.scope_tier).to eq(:organization)
      expect(cdef.organization_id).to eq(org.id)
    end

    it "still refuses an unknown scope" do
      expect { CdefScopeService.apply(cdef, scope: "everywhere") }
        .to raise_error(ArgumentError, /Unknown CDEF scope/)
    end
  end

  # The half of the feature that a "tier applied" assertion cannot see. Without
  # the NULL in the reader's IN list the tier is worse than absent: it HIDES the
  # document from the organization that owned it.
  describe "visibility" do
    it "is visible to the organization that set it" do
      CdefScopeService.apply(cdef, scope: "instance")

      expect(CdefDocument.globally_available_in(org)).to include(cdef)
    end

    it "is visible to an organization that has nothing to do with it" do
      CdefScopeService.apply(cdef, scope: "instance")

      expect(CdefDocument.globally_available_in(other_org)).to include(cdef)
    end

    it "does NOT make one organization's CDEFs visible to another" do
      org_scoped = create(:cdef_document, organization: org, globally_available: true)

      expect(CdefDocument.globally_available_in(other_org)).not_to include(org_scoped)
    end

    it "leaves a boundary-scoped CDEF out of every organization's global list" do
      boundary = create(:authorization_boundary)
      create(:boundary, authorization_boundary: boundary)
      CdefScopeService.apply(cdef, scope: "boundary", authorization_boundary_id: boundary.id)

      expect(CdefDocument.globally_available_in(org)).not_to include(cdef)
      expect(CdefDocument.globally_available_in(other_org)).not_to include(cdef)
    end
  end

  describe "#scope_tier" do
    it "reports each tier from the two columns" do
      boundary_cdef = create(:cdef_document, globally_available: false, organization: org)
      org_cdef      = create(:cdef_document, globally_available: true,  organization: org)
      inst_cdef     = create(:cdef_document, globally_available: true,  organization: nil)

      expect(boundary_cdef.scope_tier).to eq(:boundary)
      expect(org_cdef.scope_tier).to eq(:organization)
      expect(inst_cdef.scope_tier).to eq(:instance)
      expect(inst_cdef).to be_instance_wide
      expect(org_cdef).not_to be_instance_wide
    end
  end
end
