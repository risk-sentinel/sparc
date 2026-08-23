# frozen_string_literal: true

# #860 — a grant an administrator has decided will never be honoured.
#
# Filters the unmatched-grant queue. It does NOT change access: the grant was
# already refused when it arrived, and dismissing it only stops SPARC reporting
# it again. Un-dismiss and it reappears on the next sign-in that carries it.
class DismissedIdpGrant < ApplicationRecord
  belongs_to :dismissed_by, class_name: "User", optional: true

  validates :grant, presence: true, uniqueness: true

  # Stored canonically so a dismissal matches however the IdP cases the group,
  # and however the administrator typed it — the same rule IdpGrant applies when
  # it parses. Two representations of one grant would let a dismissed grant
  # reappear under a different capitalisation.
  normalizes :grant, with: ->(value) { IdpGrant.canonicalize(value) }

  def self.dismissed_grants = pluck(:grant).to_set
end
