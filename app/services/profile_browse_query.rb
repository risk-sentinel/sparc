# frozen_string_literal: true

# #908 — filtering the baseline (profile) index.
#
# `baseline_level` is the one filter on this screen that is both a real column
# and indexed, which is why the issue's "same as catalogs, plus baseline level"
# survives the audit intact where the catalog screen's Framework does not.
#
# `control_catalog_id` is offered because #928 made the source catalog something
# a user sets and changes after import — "show me every baseline drawn from Rev
# 5 HIGH" is the question that follows.
class ProfileBrowseQuery < CollectionBrowseQuery
  queries ProfileDocument, order: { created_at: :desc }

  facet :baseline_level,   label: "Baseline"
  facet :oscal_version,    label: "OSCAL version"
  facet :profile_version,  label: "Revision"
  facet :status,           label: "Import status"
  facet :lifecycle_status, label: "Status"

  facet :control_catalog_id, label: "Source catalog", choices: lambda { |scope|
    ControlCatalog.where(id: scope.distinct.select(:control_catalog_id))
                  .order(:name).pluck(:name, :id)
  }

  # Provenance is SPARC-side, not in the OSCAL — the issue's "added by".
  facet :uploaded_by_user_id, label: "Added by", choices: lambda { |scope|
    User.where(id: scope.distinct.select(:uploaded_by_user_id))
        .order(:email).map { |user| [ user.display_name.presence || user.email, user.id ] }
  }

  facet :created, label: "Created", type: :date, column: :created_at
end
