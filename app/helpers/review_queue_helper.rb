# frozen_string_literal: true

# #630 / #888 — the review queue mixes three document types in one list, so
# every row has to work out its own show and approve/reject routes. That lived
# as an inline `case` in the table; with a card view it would have had to live
# in two places, and two copies of a route table is how a card ends up
# approving the wrong thing.
module ReviewQueueHelper
  def review_queue_routes(doc)
    case doc
    when ControlCatalog
      { label: "Control Catalog", show: control_catalog_path(doc),
        approve: approve_control_catalog_path(doc), reject: reject_control_catalog_path(doc) }
    when ProfileDocument
      { label: "Profile", show: profile_document_path(doc),
        approve: approve_profile_document_path(doc), reject: reject_profile_document_path(doc) }
    when CdefDocument
      { label: "CDEF", show: cdef_document_path(doc),
        approve: approve_cdef_document_path(doc), reject: reject_cdef_document_path(doc) }
    else
      # A new reviewable type must not render an approve button pointing
      # nowhere. Without routes the partial shows no actions, which is the
      # safe failure.
      { label: doc.class.name.titleize, show: nil, approve: nil, reject: nil }
    end
  end

  # #633 — the baseline diff is the reason a reviewer can sign off on a
  # profile's control selection, so the card states it in prose rather than
  # dropping the column the table has.
  def baseline_review_summary(doc, reviews)
    return nil unless doc.is_a?(ProfileDocument)

    review = reviews&.dig(doc)
    return nil if review.blank?

    parts = [ "Baseline #{review.level || '—'}: #{review.selected_count}/#{review.expected_count} selected" ]
    parts << "#{review.missing.size} missing" if review.missing.any?
    parts << "#{review.extra.size} extra" if review.extra.any?
    parts << "ODP #{review.odp_customized_count}/#{review.odp_total_count} customized"
    parts.join(" · ")
  end
end
