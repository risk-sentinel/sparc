# frozen_string_literal: true

# #908 — filtering the evidence index.
#
# This screen already had filters, hand-written into the view as a GET form with
# its own dropdowns. Moving them here is not tidying: that form re-emitted `q`
# and `view` as hidden fields but **dropped `per_page`**, so applying a filter
# silently reset a user's page size. Every screen carrying its own form is a
# screen that can carry its own version of that bug.
#
# `source` is a real column that was never faceted — the issue asked for it and
# it costs nothing.
#
# "Added by" was cut from #908 and shipped in #934. Evidence recorded provenance
# only as `collected_by`, a free-text string written at upload from the user's
# display name — its values do not resolve to accounts, so a facet built on it
# would go stale the moment someone was renamed. It needed a
# `collected_by_user_id` column and a backfill, which is a migration, so it was
# called out rather than approximated. That column now exists and the facet
# below filters on it.
#
# Rows the backfill could not resolve — an unmatched or ambiguous name, or an
# auto-fetched artifact that predates #934 and carries no collector at all —
# have a null FK and match no "added by" value. That is the honest result: they
# are unattributed, and a filter that swept them into someone's bucket would be
# asserting something the data does not say.
class EvidenceBrowseQuery < CollectionBrowseQuery
  queries Evidence, order: { created_at: :desc }

  facet :type,   label: "Type",   column: :evidence_type
  facet :status, label: "Status"
  facet :source, label: "Source"

  facet :authorization_boundary_id, label: "Authorization boundary", choices: lambda { |scope|
    AuthorizationBoundary.where(id: scope.distinct.select(:authorization_boundary_id))
                         .order(:name).pluck(:name, :id)
  }

  # Reached through the link table, and matched across every accepted spelling
  # of a control id ("AC-01", "ac-1", "AC-1") rather than the one the user
  # happened to type.
  facet :control_id, label: "Control", type: :text, narrow: lambda { |scope, value|
    scope.where(id: EvidenceControlLink.where(control_id: ControlId.forms(value)).select(:evidence_id))
  }

  # #934 — the issue's "added by", on the FK rather than the name string.
  # Service accounts appear here alongside people, which is the point: an
  # assessor asking what a submission pipeline provided gets an answer.
  facet :collected_by_user_id, label: "Added by", choices: lambda { |scope|
    User.where(id: scope.distinct.select(:collected_by_user_id))
        .order(:email).map { |user| [ user.display_label.presence || user.email, user.id ] }
  }

  facet :collected, label: "Collected", type: :date, column: :collected_at

  private

  # Evidence searches its filename too — a user looking for what they uploaded
  # generally remembers the file, not the title they gave it.
  def apply_search(scope)
    # #888 — this screen searched on `search` while everything else used `q`.
    # Both are still honoured so existing links and bookmarks keep working.
    term = (@params[:q].presence || @params[:search].presence)
    return scope if term.blank?

    pattern = "%#{Evidence.sanitize_sql_like(term)}%"
    scope.where("title ILIKE :q OR description ILIKE :q OR original_filename ILIKE :q", q: pattern)
  end
end
