# frozen_string_literal: true

# #1039 — "provided by" on an authoritative source.
#
# `organization_id` already existed, and `organizations` carries a single
# `contact_person` / `contact_email`. Neither answers the question an assessor
# actually asks, which is "who do I ask about THIS reference" — one contact per
# organization is shared by every source that organization ever contributed.
#
# Owner-decided 2026-08-23: free text on the resource, not a `teams` table.
# The provider of an authoritative source is very often an external body — NIST,
# a CSP, another agency — that SPARC does not otherwise model and should not
# have to. A first-class Team would be a new domain concept with its own RBAC
# and API surface, introduced in the last bundle before a release.
#
# `provided_by_contact` holds an email OR a phone number and is deliberately
# NOT validated as either: an external provider's contact is frequently neither,
# and a validation that rejects a real answer is worse than no validation. The
# form ghosts the expected shape as placeholder text instead.
class AddProvidedByToBackMatterResources < ActiveRecord::Migration[8.1]
  def change
    add_column :back_matter_resources, :provided_by_team, :string
    add_column :back_matter_resources, :provided_by_contact, :string
  end
end
