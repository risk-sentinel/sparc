# frozen_string_literal: true

# NIST control order, in one place.
#
# THE DEFECT
#
# A control list read `ac-1, ac-14, ac-17, ac-18, ac-19, ac-2, ac-20, ac-22,
# ac-3, ac-7, ac-8` — lexicographic, so `ac-14` sorts before `ac-2`. On the SAR
# screen that is what shipped, because the list was ordered by `row_order`, and
# `row_order` is assigned sequentially at import (sar_excel_parser_service.rb:47)
# from whatever order the source spreadsheet happened to be in. It records
# ARRIVAL order and had been standing in for control order.
#
# The SSP screen looked right only because its view re-sorted the page in Ruby
# with a zero-padding `gsub`. That cannot fix a PAGINATED list: sorting the 50
# rows already fetched leaves the page BOUNDARIES wrong, so the ordering has to
# happen in SQL.
#
# WHY NOT `sort_id`
#
# `catalog_controls.sort_id` is NIST's own ordering and is populated on all
# 4,054 rows — it is the authority, and `profile_documents` already uses it. But
# a document's controls are not catalog rows; reaching it means joining the
# catalog on every paginated query, and a control the catalog does not carry
# (a custom or withdrawn one) would sort nowhere. This expression derives the
# same ordering from the identifier itself, which every control has.
#
# It matches `ControlId.padded`, which the class documents as "SPARC's display
# and sort convention" — family, then base number, then enhancement.
module ControlOrdering
  extend ActiveSupport::Concern

  # family, base number, enhancement number, then the raw id as a tiebreak.
  #
  # `control_family` is used when the table HAS it — it is nullable everywhere it
  # exists, so it falls back to the identifier's prefix, which is what the family
  # filter already does. `ssp_controls` and `catalog_controls` do not carry the
  # column at all, hence building this per model rather than assuming a shape.
  def self.order_sql(model)
    family =
      if model.column_names.include?("control_family")
        "COALESCE(NULLIF(control_family, ''), UPPER(SPLIT_PART(control_id, '-', 1)))"
      else
        "UPPER(SPLIT_PART(control_id, '-', 1))"
      end

    <<~SQL.squish
      #{family},
      COALESCE(NULLIF(SUBSTRING(control_id FROM '[0-9]+'), '')::int, 0),
      COALESCE(NULLIF(SPLIT_PART(SPLIT_PART(control_id, '.', 2), '.', 1), '')::int, 0),
      control_id
    SQL
  end

  included do
    # `reorder`, not `order`: these tables carry a `row_order` default in places,
    # and appending to it would leave arrival order winning.
    scope :in_control_order, -> { reorder(Arel.sql(ControlOrdering.order_sql(self))) }
  end

  class_methods do
    # For a collection already loaded into memory (a view grouping controls by
    # family, say). Same ordering as the scope, expressed in Ruby.
    def control_sort_key(control_id)
      ControlId.padded(control_id).downcase
    end
  end
end
