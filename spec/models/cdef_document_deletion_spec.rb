# frozen_string_literal: true

require "rails_helper"

# A CDEF attached to a boundary is that boundary's component inventory, and its
# scan runs and scanner findings resolve through it. Deleting one out from under
# a boundary leaves the boundary quietly less covered than its owner believes.
#
# CdefDocument includes SafeDestroyable and already counts BoundaryCdefDocument
# in `deletion_dependencies`, so the guard exists — but an unexercised guard is
# not a guarantee. These specs hold it in place, and cover the #887 component
# index alongside it, since adding an association with a foreign key and no
# `dependent:` would break deletion entirely.
RSpec.describe CdefDocument, "deletion guards", type: :model do
  let(:document) { create(:cdef_document) }

  def attach_to_boundary(doc)
    boundary = create(:boundary)
    BoundaryCdefDocument.create!(boundary: boundary, cdef_document: doc)
    boundary
  end

  describe "when the CDEF is used by a boundary" do
    before { attach_to_boundary(document) }

    it "refuses to delete it" do
      expect(document.destroy).to be_falsey
      expect(CdefDocument.where(id: document.id)).to exist
    end

    it "explains why, naming the dependency" do
      document.destroy
      expect(document.errors[:base].join).to match(/boundary environment/i)
    end

    # The join row must survive too — a partially applied delete would detach
    # the component while leaving the CDEF in place.
    it "leaves the boundary link intact" do
      expect { document.destroy }
        .not_to change { BoundaryCdefDocument.where(cdef_document_id: document.id).count }
    end

    it "still refuses when the CDEF is attached to several boundaries" do
      attach_to_boundary(document)
      expect(document.destroy).to be_falsey
    end

    it "allows deletion once it is detached from every boundary" do
      BoundaryCdefDocument.where(cdef_document_id: document.id).destroy_all

      expect(document.destroy).to be_truthy
      expect(CdefDocument.where(id: document.id)).not_to exist
    end
  end

  describe "when the CDEF is not used by any boundary" do
    it "deletes normally" do
      expect(document.destroy).to be_truthy
    end

    # #887 — cdef_components has a foreign key. Without `dependent: :delete_all`
    # on the association, every delete of an indexed CDEF fails on that
    # constraint, which would break the existing bulk-delete screen.
    it "takes its indexed components with it" do
      CdefComponent.create!(cdef_document: document, component_uuid: SecureRandom.uuid)

      expect { document.destroy }.to change { CdefComponent.where(cdef_document_id: document.id).count }.to(0)
      expect(CdefDocument.where(id: document.id)).not_to exist
    end

    it "leaves no orphaned component rows behind" do
      CdefComponent.create!(cdef_document: document, component_uuid: SecureRandom.uuid)
      document.destroy

      expect(CdefComponent.where.missing(:cdef_document).count).to be_zero
    end
  end

  describe "a CDEF that is indexed AND used by a boundary" do
    # The guard must win over the cascade: SafeDestroyable is included before
    # the associations that declare `dependent:`, so it runs first. If that
    # ordering ever changed, the components would be deleted before the guard
    # aborted, leaving the CDEF present but silently unindexed.
    it "keeps its components when deletion is refused" do
      CdefComponent.create!(cdef_document: document, component_uuid: SecureRandom.uuid)
      attach_to_boundary(document)

      expect { document.destroy }
        .not_to change { CdefComponent.where(cdef_document_id: document.id).count }
    end
  end
end
