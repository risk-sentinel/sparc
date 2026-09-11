# frozen_string_literal: true

require "rails_helper"

# #1044 — the raw `admin?` call sites that SURVIVED the triage, pinned.
#
# `admin?` (the column) is the dedicated break-glass account; the `instance_administrator?`
# predicate is authority, which an IdP can grant for a window. 105 call sites
# were swapped to authority. The handful below deliberately were not, and each
# reason is recorded in docs/dev/1044_admin_authority_triage.md.
#
# This spec exists because the two are one character apart in meaning and
# indistinguishable at a glance. A NEW raw `admin?` is almost always the wrong
# one — it denies a legitimate time-boxed administrator, quietly, in a way no
# other test would notice. Adding one here is cheap; it just has to be a
# decision rather than a reflex.
RSpec.describe "raw admin? call sites are a closed, decided list (#1044)" do
  # file => number of raw `.admin?` / bare `admin?` GUARD or VALUE sites allowed
  def approved_sites
    {
      # SEPARATION OF DUTIES — owner-decided 2026-08-21: "admin is global
      # authority and has absolute reign, break-glass type of use." The
      # exemption belongs to the ACCOUNT. A person holding a time-boxed grant
      # must not be able to approve what they themselves submitted.
      "app/services/document_approval_service.rb" => 1,
      "app/services/finding_disposition_service.rb" => 1,

      # ESCALATION BOUNDARY — only the break-glass account may set the `admin`
      # COLUMN on another user. Otherwise an afternoon-long grant could mint a
      # permanent administrator, and "users.admin is unreachable from any claim"
      # would hold only on paper.
      "app/services/user_provisioning_service.rb" => 1,

      # DISPLAYING / SERIALISING THE ATTRIBUTE — these report what the column
      # says. They are not gates.
      "app/views/admin/users/show.html.erb" => 1,
      "app/views/admin/users/index.html.erb" => 1,
      "app/controllers/admin/users_controller.rb" => 1,
      "app/controllers/api/v1/users_controller.rb" => 1,

      # TELLING THE TWO APART — admin_authority_metadata exists precisely to
      # distinguish break-glass from a time-boxed administrator in the audit
      # trail. It has to read the column to do that.
      "app/models/audit_event.rb" => 1,

      # THE ACCOUNT'S OWN LIFECYCLE — protect_last_active_admin and
      # last_active_admin? guard the break-glass account from being deactivated
      # into an unrecoverable instance. That is about the account existing, not
      # about who may act. Plus instance_administrator?'s own base case.
      "app/models/user.rb" => 3
    }
  end

  it "has no raw admin? outside the approved list" do
    pattern = /(?<![.\w])admin\?|\.admin\?/
    offenders = []

    Dir.glob(Rails.root.join("app/**/*.{rb,erb}")).sort.each do |path|
      rel = path.sub("#{Rails.root}/", "")
      count = File.readlines(path).count do |line|
        next false if line.strip.start_with?("#")
        next false if line.include?("instance_administrator?")
        next false if line.include?("def admin?")

        line.match?(pattern)
      end
      next if count.zero?

      allowed = approved_sites[rel] || 0
      offenders << "#{rel}: #{count} raw admin? site(s), #{allowed} approved" if count > allowed
    end

    expect(offenders).to be_empty, <<~MSG
      Raw `admin?` appears where the triage did not approve it:

        #{offenders.join("\n  ")}

      `admin?` is the break-glass ACCOUNT. For "may act as an administrator",
      use `instance_administrator?` — otherwise an IdP-granted, time-boxed
      administrator is denied, silently.

      If the site genuinely means the break-glass account, add it to
      approved_sites above AND record why in
      docs/dev/1044_admin_authority_triage.md.
    MSG
  end
end
