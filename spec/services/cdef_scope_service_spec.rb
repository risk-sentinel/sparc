# frozen_string_literal: true

require "rails_helper"

# #929 — CDEF is the odd one out. It carries no `authorization_boundary_id`;
# its scope is `boundary_cdef_documents` rows against a boundary's environments
# plus the `globally_available` flag. That was applied inline at upload in
# FileUploadable and changed by no route afterwards, which is the same defect
# the four FK-bearing types had in a different mechanism.
RSpec.describe CdefScopeService do
  let(:cdef)   { create(:cdef_document) }
  let(:source) { create(:authorization_boundary, name: "Source ATO") }
  let(:target) { create(:authorization_boundary, name: "Target ATO") }

  let!(:source_envs) { [ create(:boundary, authorization_boundary: source), create(:boundary, authorization_boundary: source) ] }
  let!(:target_envs) { [ create(:boundary, authorization_boundary: target) ] }

  def linked_boundary_ids(document)
    BoundaryCdefDocument.where(cdef_document_id: document.id).pluck(:boundary_id)
  end

  describe "scoping to a boundary" do
    it "links the CDEF to every environment of that boundary and records it" do
      described_class.apply(cdef, scope: "boundary", authorization_boundary_id: source.id)

      expect(linked_boundary_ids(cdef)).to match_array(source_envs.map(&:id))
      expect(described_class.current_boundary_id(cdef.reload)).to eq(source.id)
      expect(cdef.globally_available).to be(false)
    end

    it "is idempotent — re-applying the same scope does not duplicate links" do
      2.times { described_class.apply(cdef, scope: "boundary", authorization_boundary_id: source.id) }

      expect(linked_boundary_ids(cdef).size).to eq(source_envs.size)
    end

    it "refuses a boundary-specific scope with no boundary" do
      expect {
        described_class.apply(cdef, scope: "boundary", authorization_boundary_id: nil)
      }.to raise_error(ArgumentError, /needs an authorization boundary/i)
    end

    it "refuses a boundary that no longer exists, writing nothing" do
      missing = AuthorizationBoundary.maximum(:id).to_i + 1000

      expect {
        described_class.apply(cdef, scope: "boundary", authorization_boundary_id: missing)
      }.to raise_error(ArgumentError, /no longer exists/i)
      expect(linked_boundary_ids(cdef)).to be_empty
    end
  end

  describe "re-pointing from one boundary to another" do
    before { described_class.apply(cdef, scope: "boundary", authorization_boundary_id: source.id) }

    it "moves the links to the new boundary's environments" do
      described_class.apply(cdef, scope: "boundary", authorization_boundary_id: target.id)

      expect(linked_boundary_ids(cdef)).to match_array(target_envs.map(&:id))
      expect(described_class.current_boundary_id(cdef.reload)).to eq(target.id)
    end

    # Environments can also be given CDEFs directly from the boundary's own
    # form (BoundariesController#sync_cdef_documents). Clearing every link on a
    # re-point would silently destroy assignments this service never made.
    it "leaves a link made outside this service alone" do
      unrelated = create(:boundary, authorization_boundary: create(:authorization_boundary))
      BoundaryCdefDocument.create!(boundary: unrelated, cdef_document: cdef)

      described_class.apply(cdef, scope: "boundary", authorization_boundary_id: target.id)

      expect(linked_boundary_ids(cdef)).to include(unrelated.id)
    end
  end

  describe "making a CDEF globally available" do
    before { described_class.apply(cdef, scope: "boundary", authorization_boundary_id: source.id) }

    it "drops the boundary links and clears the recorded boundary" do
      described_class.apply(cdef, scope: "global")

      expect(cdef.reload.globally_available).to be(true)
      expect(linked_boundary_ids(cdef)).to be_empty
      expect(described_class.current_boundary_id(cdef)).to be_nil
    end

    it "records the organization so the org-wide composition scope resolves" do
      organization = create(:organization)

      described_class.apply(cdef, scope: "global", organization_id: organization.id)

      expect(cdef.reload.organization_id).to eq(organization.id)
    end
  end

  describe "guards" do
    it "refuses an unknown scope rather than silently doing nothing" do
      expect {
        described_class.apply(cdef, scope: "sideways", authorization_boundary_id: source.id)
      }.to raise_error(ArgumentError, /Unknown CDEF scope/i)
    end

    # #466 — re-scoping upstream content would flip `globally_available` on a
    # document the AWS Labs refresh job owns, removing it from every other
    # boundary's composition until the next refresh undid it.
    it "refuses to re-scope an AWS Labs-sourced CDEF" do
      upstream = create(:cdef_document, import_metadata: { "source_type" => "aws_labs" })

      expect {
        described_class.apply(upstream, scope: "boundary", authorization_boundary_id: source.id)
      }.to raise_error(ArgumentError, /AWS Labs/i)
      expect(linked_boundary_ids(upstream)).to be_empty
    end
  end
end
