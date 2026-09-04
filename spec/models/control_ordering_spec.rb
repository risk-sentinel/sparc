# frozen_string_literal: true

require "rails_helper"

# Control lists read `ac-1, ac-14, ac-17, ac-18, ac-19, ac-2, ac-20, ac-22,
# ac-3, ac-7, ac-8` — lexicographic, so `ac-14` sorted before `ac-2`.
#
# The SAR screen ordered by `row_order`, which is assigned sequentially at
# import from whatever order the source spreadsheet was in, so it records
# ARRIVAL order. The SSP screen looked right only because its view re-sorted the
# fetched page in Ruby — which cannot fix a PAGINATED list, since sorting the 50
# rows already fetched leaves the page BOUNDARIES wrong. Hence a SQL scope.
RSpec.describe ControlOrdering do
  # Deliberately inserted in the wrong order, and including the two cases a
  # naive string sort gets wrong: a two-digit base (ac-14 vs ac-2) and a
  # two-digit enhancement (ac-2.10 vs ac-2.2).
  let(:scrambled) { %w[ac-14 at-2 ac-2.10 ac-1 ac-22 ac-2 at-1 ac-2.2 ac-3 ac-2.1] }
  let(:expected)  { %w[ac-1 ac-2 ac-2.1 ac-2.2 ac-2.10 ac-3 ac-14 ac-22 at-1 at-2] }

  describe "the SQL scope" do
    let(:document) { create(:sar_document) }

    before do
      scrambled.each_with_index do |cid, i|
        document.sar_controls.create!(control_id: cid, title: cid.upcase,
                                      control_family: cid.split("-").first.upcase,
                                      row_order: i)
      end
    end

    it "orders by family, base number then enhancement — not lexicographically" do
      expect(document.sar_controls.in_control_order.pluck(:control_id)).to eq(expected)
    end

    it "overrides row_order rather than appending to it" do
      # `row_order` here is deliberately the scrambled insertion order, which is
      # exactly the arrival order that was standing in for control order.
      expect(document.sar_controls.in_control_order.pluck(:row_order))
        .not_to eq(document.sar_controls.order(:row_order).pluck(:row_order))
    end

    it "still orders when control_family is NULL, from the identifier" do
      document.sar_controls.update_all(control_family: nil)
      expect(document.sar_controls.in_control_order.pluck(:control_id)).to eq(expected)
    end
  end

  describe "the in-memory key, for views that group before rendering" do
    it "produces the same order as the scope" do
      sorted = scrambled.sort_by { |cid| SarControl.control_sort_key(cid) }
      expect(sorted).to eq(expected)
    end

    it "agrees across every model that lists controls" do
      keys = [ SarControl, SspControl, SapControl, CdefControl, CatalogControl ]
             .map { |m| scrambled.sort_by { |cid| m.control_sort_key(cid) } }
      expect(keys.uniq.length).to eq(1)
      expect(keys.first).to eq(expected)
    end
  end

  # `ssp_controls` and `catalog_controls` have no `control_family` column, so the
  # expression is built per model. A shared literal would have raised
  # ActiveRecord::StatementInvalid on those two.
  it "builds an expression valid for models with and without control_family" do
    [ SarControl, SspControl, SapControl, CdefControl, CatalogControl ].each do |model|
      expect { model.in_control_order.limit(1).to_a }.not_to raise_error,
        "#{model} cannot execute its ordering"
    end
  end
end
