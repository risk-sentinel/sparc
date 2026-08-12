# frozen_string_literal: true

# #908 — filtering the POA&M index.
#
# The issue asked for status and date range here, which is the narrowest of the
# five proposals and the closest to what the data supports. Both ship, plus the
# OSCAL/revision pair every document screen now offers.
#
# The scope is ALWAYS supplied by the caller. POA&Ms are boundary-scoped, and
# `boundary_scoped_relation` decides what a user may see; re-deriving that here
# would be a second place for the access rule to live and eventually disagree.
class PoamBrowseQuery < CollectionBrowseQuery
  queries PoamDocument, order: { created_at: :desc }

  facet :status,           label: "Import status"
  facet :lifecycle_status, label: "Status"
  facet :oscal_version,    label: "OSCAL version"
  facet :poam_version,     label: "Revision"

  facet :authorization_boundary_id, label: "Authorization boundary", choices: lambda { |scope|
    AuthorizationBoundary.where(id: scope.distinct.select(:authorization_boundary_id))
                         .order(:name).pluck(:name, :id)
  }

  facet :uploaded_by_user_id, label: "Added by", choices: lambda { |scope|
    User.where(id: scope.distinct.select(:uploaded_by_user_id))
        .order(:email).map { |user| [ user.display_name.presence || user.email, user.id ] }
  }

  facet :created, label: "Created", type: :date, column: :created_at
end
