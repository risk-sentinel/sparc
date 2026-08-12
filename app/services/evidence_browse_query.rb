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
# The issue also asked for "added by". Evidence records provenance as
# `collected_by`, a free-text string written at upload from the user's display
# name, not a foreign key — so its values do not resolve to accounts and a
# facet built on it would go stale the moment someone's name changed. Filtering
# it properly needs a `collected_by_user_id` column and a backfill; that is a
# migration, and it is called out rather than approximated.
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
