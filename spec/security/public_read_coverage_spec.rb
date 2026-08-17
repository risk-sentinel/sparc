# frozen_string_literal: true

require "rails_helper"

# #974 — the deliverable that makes the public-read rule structural rather than a
# convention people have to remember.
#
# `skip_before_action :require_authentication` makes an action unconditionally
# public. The Controls layer is supposed to pair it with
# `require_authentication_unless_public_controls`, so the action is public only
# when `SPARC_PUBLIC_CATALOGS=true`. Two lines that have to agree, repeated per
# controller.
#
# `CdefDocumentsController` and `ControlFamiliesController` had the skip and not
# the gate. Nothing failed. No test noticed. The entire CDEF library — 231
# documents on the instance where this was found — and every control-family page
# were readable by anyone who could reach the app, and **no configuration could
# turn it off**. It survived because omitting the second line produces no error:
# the screen simply stops requiring a login.
#
# So the rule has to be enforced by enumeration. A controller that skips
# authentication either declares the conditional gate — in practice via
# `public_controls_read`, which writes both halves from one declaration — or it
# is deliberately allowlisted here with a reason.
#
# This is a STRUCTURAL check: it asserts the gate is DECLARED, not that it
# behaves. Behavioural proof of both postures lives in
# `spec/requests/public_controls_access_974_spec.rb` (request level) and
# `tests/ui-smoke/test_public_controls_974.py` (a real browser against a real
# deployment). All three are needed — this one catches the controller nobody
# thought about, the others catch a gate that does not work.
#
# NIST 800-53: AC-3 Access Enforcement, AC-6 Least Privilege,
# CM-6 Configuration Settings, CM-3 (a new public surface cannot land unreviewed).
RSpec.describe "Public read coverage (#974)", type: :request do
  # How a controller may legitimately DECLARE conditional public read.
  #
  # Both forms require a `before_action`/declaration, not a mere mention of the
  # method name. The sibling #919 spec learned this the hard way: its first
  # version matched `/authorize_\w+!/` anywhere in the file, so deleting the
  # `before_action` left the method DEFINITION behind, still matched, and the
  # spec stayed green against a controller enforcing nothing.
  let(:gate_patterns) do
    [
      /public_controls_read\s+only:/,                                   # the one-line declaration
      /before_action\s+:require_authentication_unless_public_controls/  # the legacy two-line form
    ]
  end

  # Controllers that skip authentication for reasons unrelated to the Controls
  # layer. Every entry needs a reason that survives being read aloud, because
  # adding to this list is how a real gap would be hidden.
  let(:allowed_unconditional_skips) do
    {
      # Becoming authenticated. Requiring authentication would be circular.
      "sessions"             => "sign-in form and submit; pre-authentication by definition",
      "registrations"        => "self-service sign-up, gated by SPARC_ENABLE_USER_REGISTRATION",
      "password_resets"      => "redeeming an admin-issued reset; the single-use token is the credential",
      "omniauth_callbacks"   => "IdP callback; the assertion is the credential",
      "piv_sessions"         => "PIV/mTLS sign-in; the proxy-validated client cert is the credential",
      "webauthn_sessions"    => "FIDO2 sign-in ceremony; the authenticator is the credential",
      "api/v1/sessions"      => "#573 Bearer-token to session-cookie bridge. Pre-authentication " \
                                "like its web sibling: the Bearer token IS the credential and is " \
                                "validated by ApiAuthentication#authenticate_api_token! (revocation, " \
                                "expiry, scope, CIDR allowlist) before any cookie is issued",

      # Public by design, and carrying no instance data.
      "about"                => "marketing/about pages — static product information, no records"
    }.freeze
  end

  # Every controller that skips the authentication gate, and for which actions.
  def controllers_skipping_authentication
    Rails.root.glob("app/controllers/**/*_controller.rb").each_with_object({}) do |path, acc|
      source = path.read
      next unless source.match?(/skip_before_action\s+:require_authentication/)

      key = path.relative_path_from(Rails.root.join("app/controllers"))
                .to_s.sub(/_controller\.rb\z/, "")
      acc[key] = source
    end
  end

  it "every controller that skips authentication either gates it on the flag or is allowlisted" do
    ungated = controllers_skipping_authentication.reject do |name, source|
      allowed_unconditional_skips.key?(name) || gate_patterns.any? { |p| source.match?(p) }
    end

    expect(ungated.keys).to be_empty, <<~MSG
      #{ungated.size} controller(s) skip authentication with no conditional gate and no
      allowlist entry, so their actions are public in EVERY posture and no
      configuration turns that off:

        #{ungated.keys.join("\n  ")}

      Declare `public_controls_read only: [ ... ]` (Authentication concern), or add an
      allowlist entry here with a reason. #974.
    MSG
  end

  it "the allowlist names only controllers that actually skip authentication" do
    # A stale entry is worse than no entry: it silently pre-authorises a
    # controller that may later be rewritten to serve real data.
    skipping = controllers_skipping_authentication.keys
    stale = allowed_unconditional_skips.keys - skipping

    expect(stale).to be_empty,
      "allowlist entries for controllers that no longer skip authentication — remove them: #{stale.join(', ')}"
  end

  it "every allowlist entry carries a non-trivial reason" do
    thin = allowed_unconditional_skips.select { |_, reason| reason.to_s.strip.length < 25 }

    expect(thin).to be_empty,
      "allowlist entries need a reason that explains WHY, not a placeholder: #{thin.keys.join(', ')}"
  end

  # `public_controls_read` is read-only by construction. Without this the macro
  # would be a route by which a write could be made public in one line, which is
  # precisely the mistake it exists to prevent. Untested until a mutation removing
  # the guard passed the whole suite.
  describe "the macro refuses to make a write public" do
    def controller_declaring(actions)
      Class.new(ApplicationController) { public_controls_read only: actions }
    end

    it "raises rather than exposing a mutating action" do
      %i[create update destroy edit new publish approve bulk_destroy refresh_cci import export].each do |action|
        expect { controller_declaring([ action ]) }
          .to raise_error(ArgumentError, /READ actions only/i),
              "public_controls_read accepted :#{action}, which would make a write public"
      end
    end

    it "refuses a mixed list rather than silently dropping the write" do
      expect { controller_declaring(%i[index destroy]) }
        .to raise_error(ArgumentError, /destroy/)
    end

    it "still accepts genuine read actions" do
      expect { controller_declaring(%i[index show baseline_controls]) }.not_to raise_error
    end
  end

  # The Controls layer specifically — named so a future refactor that drops one
  # of these from the public-read declaration fails here rather than silently
  # requiring a login on a screen the flag is supposed to open (or, worse,
  # opening one it is not).
  it "every Controls-layer read controller declares the conditional gate" do
    expected = %w[
      control_catalogs catalog_controls control_families
      control_mappings profile_documents cdef_documents
    ]

    missing = expected.reject do |name|
      source = Rails.root.join("app/controllers", "#{name}_controller.rb").read
      gate_patterns.any? { |p| source.match?(p) }
    end

    expect(missing).to be_empty,
      "Controls-layer controllers with no conditional public-read gate: #{missing.join(', ')}"
  end
end
