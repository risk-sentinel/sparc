# frozen_string_literal: true

# #1390 — what SPARC needs to write a boundary's FedRAMP Certification Package
# Overview (FRC-CSO-PKG, CPO-CSO-OVR):
#
#   fedramp_package       service identification and properties (package ID,
#                         provider, service name/acronym/description,
#                         certification type, website, logo, service model,
#                         deployment model, and the optional fields)
#   fedramp_contacts      the provider's contacts, a list kept on the boundary
#                         and separate from SPARC users (the overview must name
#                         at least one Security and one Sales contact)
#   fedramp_overview_from_sparc
#                         true: the address FedRAMP reports name
#                         (certificationPackageOverviewUri) is SPARC's own
#                         overview endpoint; false: the address set in
#                         fedramp_package_overview_uri (the trust center)
#
# Idempotent (docs/dev/issue_rules.md, migration rules 1–6).
class AddFedrampPackageOverviewToBoundaries < ActiveRecord::Migration[8.1]
  COLUMNS = {
    fedramp_package: [ :jsonb, { null: false, default: {} } ],
    fedramp_contacts: [ :jsonb, { null: false, default: [] } ],
    fedramp_overview_from_sparc: [ :boolean, { null: false, default: false } ]
  }.freeze

  def up
    COLUMNS.each do |name, (type, options)|
      add_column :authorization_boundaries, name, type, **options unless column_exists?(:authorization_boundaries, name)
    end
  end

  def down
    COLUMNS.each_key do |name|
      remove_column :authorization_boundaries, name if column_exists?(:authorization_boundaries, name)
    end
  end
end
