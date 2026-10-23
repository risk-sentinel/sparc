# frozen_string_literal: true

require "rails_helper"

# #1263 — a deleted document's name can be reused. Sluggable picked a free slug
# through SoftDeletable's default scope, which hides deleted rows, so it handed
# out a deleted document's slug; the uniqueness validation and the unique index
# both see deleted rows, and the save failed with "Slug has already been taken".
RSpec.describe Sluggable do
  # A local, not a constant: a constant assigned inside a `describe` block is
  # defined at top level and leaks into every other spec.
  %i[cdef_document poam_document profile_document sap_document sar_document ssp_document].each do |type|
    describe type.to_s do
      let(:name) { "Invented Reused Name #{SecureRandom.hex(3)}" }

      it "gives a document reusing a deleted one's name a slug of its own" do
        deleted = create(type, name: name)
        deleted.soft_delete!

        reused = build(type, name: name)

        expect(reused.save).to be(true), reused.errors.full_messages.join(", ")
        expect(reused.slug).not_to eq(deleted.slug)
        expect(reused.slug).to start_with(name.parameterize)
      end

      it "lets the deleted document be restored with the slug it had" do
        deleted = create(type, name: name)
        original_slug = deleted.slug
        deleted.soft_delete!
        create(type, name: name)

        deleted.restore!

        expect(deleted.reload.slug).to eq(original_slug)
        expect(deleted).to be_valid
      end

      it "still suffixes a name a live document holds" do
        live = create(type, name: name)

        expect(create(type, name: name).slug).to eq("#{live.slug}-1")
      end
    end
  end
end
