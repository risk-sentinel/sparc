# frozen_string_literal: true

require "rails_helper"

# #967 — the summary tiles on the document index screens counted the child
# records of SOFT-DELETED documents.
#
# The six document models include SoftDeletable, which adds
# `default_scope { where(deleted_at: nil) }`. The child models carry no
# equivalent scope, and each index controller computed its totals tile with a
# bare `Child.count`. So the "documents" tile was scoped and the "controls"
# tile beside it was not, and the screen contradicted itself: a demo instance
# rendered "1 Component Defs" next to "1290 Total Controls", the other 1280
# belonging to 59 soft-deleted rows.
#
# These assertions read the RENDERED TILE, not the controller ivar. The bug was
# only ever visible as a number on a screen, and a spec that reads the
# instance variable would pass against a view that rendered something else.
#
# Each example soft-deletes a document that HAS children and asserts the tile
# drops by exactly that document's child count. That is the mutation-checkable
# form: revert any one controller to `Child.count` and its example goes red,
# because the deleted document's children stay in the total.
RSpec.describe "Index summary tiles exclude soft-deleted documents (#967)", type: :request do
  let(:user) { create(:user, :admin) }

  before { sign_in_as(user) }

  # Pull the tile values out of the rendered page by LABEL rather than by
  # position — the screens do not share a tile order, and a positional index
  # would silently read the wrong tile if one screen gained a tile.
  def tile_value(label)
    pairs = response.body.scan(
      %r{sparc-hero-tile-count">\s*([\d,]+)\s*</div>\s*<div class="sparc-hero-tile-label">\s*([^<]+?)\s*</div>}m
    )
    found = pairs.find { |_count, tile_label| tile_label == label }
    raise "tile #{label.inspect} not found; tiles present: #{pairs.map(&:last).inspect}" if found.nil?

    found.first.delete(",").to_i
  end

  # Build children with EXPLICIT identifiers rather than letting the factory
  # pick them. `:profile_control` draws `control_id` from only 22 values
  # ("ac-1".."ac-22") and the model validates uniqueness within a profile, so
  # `create_list(:profile_control, 4, ...)` collides by chance — roughly a 1-in-4
  # birthday collision on four draws. That surfaced as a spec that passed on
  # most seeds and failed on 28830, which reads like flakiness and is really the
  # factory's random identifier meeting a uniqueness constraint.
  def create_children(factory, count, fk, parent, tag)
    klass = factory.to_s.classify.constantize
    Array.new(count) do |i|
      attrs = { fk => parent }
      attrs[:control_id] = "zz-#{tag}-#{i}" if klass.column_names.include?("control_id")
      create(factory, **attrs)
    end
  end

  # doc_factory      — the SoftDeletable document
  # child_factory    — its child records
  # child_fk         — the FK naming the parent
  # path             — the index route
  # label            — the tile the children are counted into
  shared_examples "a totals tile that ignores soft-deleted documents" do
    |doc_factory:, child_factory:, child_fk:, path:, label:|

    it "drops the soft-deleted document's children from the #{label.inspect} tile" do
      kept    = create(doc_factory)
      removed = create(doc_factory)
      create_children(child_factory, 2, child_fk, kept, "kept")
      create_children(child_factory, 3, child_fk, removed, "removed")

      get public_send(path)
      expect(response).to have_http_status(:ok)
      before_delete = tile_value(label)
      expect(before_delete).to be >= 5

      removed.soft_delete!

      get public_send(path)
      expect(response).to have_http_status(:ok)
      expect(tile_value(label)).to eq(before_delete - 3)
    end

    it "still counts a live document's children in the #{label.inspect} tile" do
      # Guards against the opposite failure: a fix that scoped the count so
      # aggressively it stopped counting anything would pass the example above.
      baseline = begin
        get public_send(path)
        tile_value(label)
      end

      live = create(doc_factory)
      create_children(child_factory, 4, child_fk, live, "live")

      get public_send(path)
      expect(tile_value(label)).to eq(baseline + 4)
    end
  end

  describe "GET /cdef_documents" do
    include_examples "a totals tile that ignores soft-deleted documents",
      doc_factory: :cdef_document, child_factory: :cdef_control,
      child_fk: :cdef_document, path: :cdef_documents_path, label: "Total Controls"
  end

  describe "GET /ssp_documents" do
    include_examples "a totals tile that ignores soft-deleted documents",
      doc_factory: :ssp_document, child_factory: :ssp_control,
      child_fk: :ssp_document, path: :ssp_documents_path, label: "Total Controls"
  end

  describe "GET /sar_documents" do
    include_examples "a totals tile that ignores soft-deleted documents",
      doc_factory: :sar_document, child_factory: :sar_control,
      child_fk: :sar_document, path: :sar_documents_path, label: "Total Controls"
  end

  describe "GET /profile_documents" do
    include_examples "a totals tile that ignores soft-deleted documents",
      doc_factory: :profile_document, child_factory: :profile_control,
      child_fk: :profile_document, path: :profile_documents_path, label: "Total Controls"
  end

  describe "GET /poam_documents" do
    include_examples "a totals tile that ignores soft-deleted documents",
      doc_factory: :poam_document, child_factory: :poam_item,
      child_fk: :poam_document, path: :poam_documents_path, label: "Total Items"
  end
end
