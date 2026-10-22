# frozen_string_literal: true

require "rails_helper"

# #919 — the deliverable that makes this structural rather than a one-off sweep.
#
# AuthorizationBoundaryMembershipsController shipped with no authorization from
# 2026-03-09 until v1.15.5. Nothing was designed to catch it and nothing did, for
# five months of green CI:
#
#   * Brakeman, CodeQL and Semgrep have no check for missing authorization. They
#     analyse code that exists; they cannot flag a guard that was never written.
#   * Every test exercised the permitted path. A suite that only asks "can the
#     authorized caller do this?" never asks "is anyone else stopped?"
#
# So the guard has to be a test, and it has to be enumerative: a NEW controller
# with a mutating action fails here on arrival unless it is either guarded or
# deliberately allowlisted. Removing an entry from the allowlist is then a
# reviewed act rather than an oversight.
#
# This is a STRUCTURAL check — it asserts a guard is declared, not that the guard
# is correct. Behavioural proof lives in
# spec/requests/controller_authorization_919_spec.rb, which asserts real refusals
# and is mutation-checked. Both are needed: this one catches the controller
# nobody thought about, that one catches the guard that does not work.
#
# NIST 800-53: AC-3 (access enforcement), AC-6 (least privilege),
# CM-3 (change control — a new mutating surface cannot land unreviewed).
RSpec.describe "Controller authorization coverage (#919)", type: :request do
  MUTATING_ACTIONS = %w[
    create update destroy
  ].freeze

  # Recognised ways a controller DECLARES authorization.
  #
  # These deliberately require a `before_action` (or `boundary_scoped`, which
  # installs before_actions itself) rather than merely mentioning a guard method.
  # The first version of this spec matched /authorize_\w+!/ anywhere in the file
  # and was VACUOUS: deleting `before_action :authorize_boundary_write!` left the
  # `def authorize_boundary_write!` definition behind, still matched, and the spec
  # stayed green against a controller that no longer enforced anything. A defined
  # but uninvoked guard is exactly the bug this file exists to catch.
  #
  # Caught by mutation-checking the spec itself — which is the only way this class
  # of hole ever surfaces.
  GUARD_PATTERNS = [
    /before_action\s+:authorize_\w+!/,   # authorize_permission! / authorize_admin! / bespoke
    /boundary_scoped\s+\w+/,             # BoundaryScopedDocument wires read/write guards
    /before_action\s+:require_admin/,
    /before_action\s+:verify_authorized/
  ].freeze

  # Controllers with mutating actions that legitimately have no authorization
  # guard. Every entry needs a reason, and the reason has to survive being read
  # aloud. Adding to this list is how a real gap would be hidden, so it is
  # deliberately small and deliberately annotated.
  ALLOWED_UNGUARDED = {
    # Authentication endpoints: these are how an unauthenticated user becomes
    # authenticated. Requiring authorization would be circular.
    "sessions"            => "sign-in; pre-authentication by definition",
    "api/v1/sessions"     => "#573 Bearer-token to session-cookie bridge " \
                             "(POST /api/v1/sessions/from_token). Pre-authentication like its " \
                             "web sibling: the Bearer token IS the credential, validated by " \
                             "ApiAuthentication#authenticate_api_token! (revocation, expiry, " \
                             "scope, CIDR allowlist) before a cookie is issued. Emits " \
                             "api_session_bridged / api_session_bridge_failed either way",
    "passwords"           => "password change/reset; guarded by token or current session",
    "password_resets"     => "unauthenticated reset request",
    "registrations"       => "self-service sign-up, gated by SPARC_ENABLE_USER_REGISTRATION",
    "omniauth_callbacks"  => "IdP callback; the assertion is the credential",
    "piv_sessions"        => "PIV/mTLS sign-in; the client cert is the credential",
    "webauthn_sessions"   => "FIDO2 sign-in ceremony",
    "webauthn_credentials" => "a user manages their OWN security keys; scoped to current_user",
    "profiles"            => "a user edits their OWN profile; scoped to current_user",

    # Enforced one layer down, proven by spec rather than asserted here.
    "promotion_queue" => "approve!/reject! re-check can_approve? inside " \
                         "BackMatterResourcePromotionService before mutating; #index self-filters " \
                         "per record. Verified 2026-08-11 — service-layer enforcement, not a gap",

    # Unauthenticated by design.
    "security/csp_reports" => "write-only CSP violation beacon posted by the BROWSER, so it " \
                     "cannot carry a session. Inherits ActionController::Base deliberately, " \
                     "skips forgery protection, caps the body at 8 KB and is Rack::Attack " \
                     "rate-limited. Requiring authorization would discard the reports we " \
                     "added it to collect",

    # Non-persisting despite POST verbs.
    "api/v1/translations" => "stateless HDF/OSCAL translation endpoints — they take an uploaded " \
                      "payload, translate it and return it. Nothing is written to SPARC's " \
                      "database, so there is no object to authorize against. Verified " \
                      "2026-08-11: no save/create!/update! anywhere in the controller. If a " \
                      "translation ever persists, REMOVE THIS ENTRY"
  }.freeze

  # Controllers reachable from the routing table, so a controller that exists but
  # is unroutable does not fail this spec, and one added to routes does.
  def routed_controllers_with_mutating_actions
    Rails.application.routes.routes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |route, acc|
      controller = route.defaults[:controller]
      action     = route.defaults[:action]
      next if controller.blank? || action.blank?
      next if controller.start_with?("rails/", "active_storage/", "action_mailbox/", "turbo/")

      acc[controller] << action if MUTATING_ACTIONS.include?(action) || mutating_custom_action?(route)
    end
  end

  # Custom member/collection actions are where the interesting gaps hide — a
  # controller can look read-only on the seven REST verbs and still expose
  # `approve`, `publish` or `bulk_destroy`. Anything reachable by a non-GET verb
  # mutates by definition.
  def mutating_custom_action?(route)
    verb = route.verb.to_s
    verb.present? && !verb.match?(/GET|HEAD/)
  end

  def controller_source(controller_path)
    path = Rails.root.join("app/controllers", "#{controller_path}_controller.rb")
    path.exist? ? path.read : nil
  end

  # Walks up the inheritance chain, so a controller inheriting its guard from a
  # base class (Api::V1::BaseController, DocumentBaseController) is not reported.
  def guarded?(controller_path)
    klass = "#{controller_path.camelize}Controller".safe_constantize
    return false unless klass

    klass.ancestors.each do |ancestor|
      next unless ancestor.is_a?(Class) && ancestor.name&.end_with?("Controller")

      src = controller_source(ancestor.name.delete_suffix("Controller").underscore)
      next if src.nil?
      return true if GUARD_PATTERNS.any? { |re| src.match?(re) }
    end
    false
  end

  # #1244 — PER ACTION, not per controller. A controller with ONE guarded action
  # used to count as guarded: AuthorizationBoundariesController guarded only
  # bulk_destroy, and its update, destroy and ATO package actions shipped open.
  #
  # Asked of Rails itself, not of the source text: for each routed mutating
  # action, does a guard callback actually run for THAT action once its
  # only:/except: conditions are applied? `only:`/`except:` are
  # AbstractController::Callbacks::ActionFilter objects in the callback's
  # if/unless lists, which answer `match?` for a controller whose action_name is
  # set. Any other condition (a symbol or proc) cannot be evaluated here, so the
  # guard counts as applying; this check is structural, and the behavioural
  # proof is in the request specs.
  #
  # An action may also guard itself inline (`authorize_permission!` inside the
  # method body), which a callback walk cannot see, so the method's own source
  # is read as a fallback.
  GUARD_FILTER = /\A(authorize_\w+!|require_admin!?|verify_authorized)\z/

  # Actions with no guard of their own whose controller IS otherwise guarded.
  # Same rules as ALLOWED_UNGUARDED: each needs a reason that survives being
  # read aloud.
  approval = "DocumentApprovalService#approve!/#reject! return forbidden unless " \
             "can_approve? (the type's .approve key, policy_manager, or an instance " \
             "administrator) before any change: service-layer enforcement, proven in " \
             "spec/services/document_approval_service_spec.rb (#630)"
  ALLOWED_UNGUARDED_ACTIONS = {
    "control_catalogs#approve"             => approval,
    "control_catalogs#reject"              => approval,
    "profile_documents#approve"            => approval,
    "profile_documents#reject"             => approval,
    "cdef_documents#approve"               => approval,
    "cdef_documents#reject"                => approval,
    "api/v1/control_catalogs#approve"      => approval,
    "api/v1/control_catalogs#reject"       => approval,
    "api/v1/profile_documents#approve"     => approval,
    "api/v1/profile_documents#reject"      => approval,
    "api/v1/cdef_documents#approve"        => approval,
    "api/v1/cdef_documents#reject"         => approval,
    "api/v1/authorization_boundaries#assign_organization" =>
      "BoundaryOrganizationAssigner applies the organization-admin matrix (#770) and " \
      "raises MoveRequiresAdminError (403) before any change; proven in " \
      "spec/services/boundary_organization_assigner_spec.rb",
    "authoritative_sources#create"         =>
      "any signed-in user may register an authoritative source (owner, 2026-10-21: " \
      "correct as is); spec/requests/authoritative_sources_create_spec.rb",
    "api/v1/authoritative_sources#create"  =>
      "as the web action (owner, 2026-10-21); spec/requests/api/v1/authoritative_sources_spec.rb",
    "api/v1/cdef_coverage#destroy_run"     =>
      "deletes only a run the caller can see, through a scoped lookup (owner, " \
      "2026-10-21: correct as is); spec/requests/api/v1/cdef_coverage_spec.rb"
  }.freeze

  def guard_applies?(callback, controller)
    passes = Array(callback.instance_variable_get(:@if)).all? do |condition|
      condition.respond_to?(:match?) ? condition.match?(controller) : true
    end
    blocked = Array(callback.instance_variable_get(:@unless)).any? do |condition|
      condition.respond_to?(:match?) && condition.match?(controller)
    end
    passes && !blocked
  end

  def inline_guard?(klass, action)
    return false unless klass.method_defined?(action) || klass.private_method_defined?(action)

    file, line = klass.instance_method(action).source_location
    return false unless file && File.exist?(file)

    lines = File.readlines(file)[(line - 1)..]
    indent = lines.first[/\A\s*/]
    body = lines.take_while.with_index { |l, i| i.zero? || !l.start_with?("#{indent}end") }
    body.join.match?(/authorize_\w+!|raise\s+NotAuthorizedError/)
  end

  def action_guarded?(controller_path, action)
    klass = "#{controller_path.camelize}Controller".safe_constantize
    return false unless klass

    # A route to an action the controller does not define answers 404 (three
    # import_json routes do): nothing runs, so there is nothing to guard.
    return true unless klass.action_methods.include?(action)

    controller = klass.new
    controller.action_name = action
    klass._process_action_callbacks.any? do |callback|
      callback.kind == :before && callback.filter.is_a?(Symbol) &&
        callback.filter.to_s.match?(GUARD_FILTER) && guard_applies?(callback, controller)
    end || inline_guard?(klass, action)
  end

  it "every routed mutating action runs an authorization guard (#1244)" do
    offenders = routed_controllers_with_mutating_actions.flat_map do |controller, actions|
      next [] if ALLOWED_UNGUARDED.key?(controller)

      actions.uniq.reject do |action|
        ALLOWED_UNGUARDED_ACTIONS.key?("#{controller}##{action}") || action_guarded?(controller, action)
      end.map { |action| "#{controller}##{action}" }
    end.sort

    expect(offenders).to be_empty, <<~MSG
      These mutating actions run no authorization guard, though their controller
      may guard others:

        #{offenders.join("\n  ")}

      Add the action to a guard's only:/except: list, guard it inline, or, if it is
      genuinely safe, list it in ALLOWED_UNGUARDED_ACTIONS with a reason.
    MSG
  end

  it "keeps the action allowlist honest — no entry is guarded, unrouted or undefined" do
    routed = routed_controllers_with_mutating_actions
    stale = ALLOWED_UNGUARDED_ACTIONS.keys.select do |entry|
      controller, action = entry.split("#")
      klass = "#{controller.camelize}Controller".safe_constantize
      !routed[controller].include?(action) || klass.nil? ||
        !klass.action_methods.include?(action) || action_guarded?(controller, action)
    end

    expect(stale).to be_empty,
      "Remove these from ALLOWED_UNGUARDED_ACTIONS (now guarded, or gone): #{stale.join(', ')}"
  end

  it "every routed controller with a mutating action declares authorization" do
    offenders = routed_controllers_with_mutating_actions.keys.reject do |controller|
      ALLOWED_UNGUARDED.key?(controller) || guarded?(controller)
    end.sort

    expect(offenders).to be_empty, <<~MSG
      These controllers expose mutating actions with no authorization guard:

        #{offenders.join("\n  ")}

      A signed-in user who knows an id or slug can invoke them. Add a guard
      (authorize_permission! scoped to the owning boundary, per
      docs/dev/919_authorization_triage.md), or — if the endpoint is genuinely
      public or enforced elsewhere — add it to ALLOWED_UNGUARDED with a reason.
      Do not add an entry to make this spec pass.
    MSG
  end

  # An allowlist nobody prunes becomes a list of forgotten holes. If a controller
  # gains a guard, its exemption must go, or the exemption silently protects the
  # NEXT regression in that file.
  it "keeps the allowlist honest — no entry is guarded or absent" do
    stale = ALLOWED_UNGUARDED.keys.select do |name|
      controller_source(name).nil? || guarded?(name)
    end

    expect(stale).to be_empty,
      "These are allowlisted but no longer need to be (guarded now, or gone). " \
      "Remove them so the exemption cannot shelter a future regression: #{stale.join(', ')}"
  end

  # The 13 controllers fixed in #919. Named explicitly so a revert is loud: the
  # generic check above would still pass if one of them regressed to a weaker but
  # still-present guard, and these are the specific files that were exploitable.
  it "the controllers fixed in #919 are still guarded" do
    fixed = %w[
      attestations back_matter_resources boundaries control_back_matter_links
      poam_findings poam_items poam_local_components poam_milestones
      poam_observations poam_remediations poam_risks
      profile_controls profile_documents
      authorization_boundary_memberships federation_peers leveraged_authorizations
    ]

    regressed = fixed.reject { |c| guarded?(c) }

    expect(regressed).to be_empty,
      "Guards added in #919 have been removed from: #{regressed.join(', ')}"
  end
end
