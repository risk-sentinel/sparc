# frozen_string_literal: true

# Who may attest here, and under which role — for the evidence form's attester
# picker (#947) and the boundary-change refresh that keeps it honest (#981).
#
# #981 — the eligible set is a property of the BOUNDARY, and the form used to
# compute it once, for the boundary the page was rendered with. Changing the
# Authorization Boundary select left the options behind, so the form offered
# `policy_manager` — instance-scoped, valid only for instance-wide evidence —
# on a boundary where `Attestation#attester_holds_the_attested_role` correctly
# refuses it. The model was right; the form had not been told.
#
# The asymmetry that makes this worth getting right is deliberate (#947): an
# instance-scoped grant satisfies `has_permission?` on EVERY boundary, so Policy
# may attest to provider / leveraged-SSP material that belongs to no system, but
# must not thereby gain authority over an individual system's evidence. A picker
# that quietly widens that is the whole defect.
#
# One service, three callers — the inline partial, the session-authenticated
# lookup, and the Bearer-only API twin — because the alternative is three places
# for the rule to drift. The query itself still lives on `Attestation`; this only
# assembles and shapes it.
#
# NIST 800-53 Controls:
#   AC-3  Access Enforcement — the offered set never exceeds what the model
#         accepts on save; the server remains the authority.
#   AC-6  Least Privilege — eligibility is derived from the `evidence.attest`
#         permission at a scope that reaches this boundary, not a role list.
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class AttesterEligibilityService
  # @param authorization_boundary_id [Integer, String, nil] nil / blank means
  #   instance-wide evidence, which has its own (wider) eligibility rule.
  def initialize(authorization_boundary_id: nil)
    @authorization_boundary_id = authorization_boundary_id.presence
  end

  # Users who may attest here, ordered for a stable picker.
  def attesters
    @attesters ||= Attestation.eligible_attesters_for(
      authorization_boundary_id: @authorization_boundary_id
    )
  end

  # { "<user id>" => [{ name:, label: }, ...] } — the roles each attester may
  # actually attest under on this boundary.
  #
  # Keyed by STRING id: this is consumed as JSON and as a Stimulus value, and
  # `JSON.parse` produces string keys either way. Keeping the Ruby side the same
  # shape means the controller never has to care which door the data came in by.
  def roles_by_attester
    @roles_by_attester ||= attesters.each_with_object({}) do |user, map|
      map[user.id.to_s] = Attestation.attestable_roles_for(
        user: user, authorization_boundary_id: @authorization_boundary_id
      ).map { |role| { name: role.name, label: role.display_name } }
    end
  end

  # The payload both front doors render, and the shape the Stimulus controller
  # expects.
  def as_json(*)
    {
      "attesters" => attesters.map { |user| { "id" => user.id, "label" => attester_label(user) } },
      "roles_by_attester" => roles_by_attester.transform_values { |roles|
        roles.map { |role| { "name" => role[:name], "label" => role[:label] } }
      }
    }
  end

  private

  # Matches the picker's existing rendering: a display name when there is one,
  # the email otherwise, never a bare id.
  def attester_label(user)
    user.display_label.presence || user.email
  end
end
