# frozen_string_literal: true

require "rails_helper"

# #894 — `disposition: "attachment"` is load-bearing, and nothing pinned it.
#
# SPARC runs ActiveStorage in Rails' DEFAULT REDIRECT MODE against S3 (there is
# no `resolve_model_to_route` anywhere in this repo and no `rails_storage_proxy`
# usage), so `/artifacts/:uuid` 302s to a presigned URL and the bytes are served
# from the bucket origin, never from SPARC's:
#
#   GET /artifacts/:uuid
#     -> 302 <app-host>/rails/active_storage/blobs/redirect/<signed_id>/<file>
#         -> 302 <bucket>.s3.<region>.amazonaws.com/...?X-Amz-Signature=...
#
# sparc-iac#269 (the cookieless userdata.* subdomain, infra pair to #515) was
# closed as not-applicable on exactly that analysis. With the infra half gone,
# the control that actually stops an uploaded HTML/SVG from executing is the
# disposition forwarded into the presigned URL as `response-content-disposition`.
#
# The fragile seam is NOT a missing argument — Rails defaults both send_data and
# send_file to attachment, and all 48 send_data call sites pass it explicitly.
# It is the KEYWORD DEFAULT in ArtifactResolvable#signed_artifact_url /
# #signed_version_url, which NEITHER caller passes:
#
#   ArtifactsController#show     -> signed_artifact_url(evidence)
#   Api::V1::ArtifactsController -> same
#
# So a one-word edit to that default silently flips every evidence download to
# inline, and no test would have failed. These assert on the EMITTED URL rather
# than on the helper's default, so the seam itself is covered.
#
# NIST 800-53: SC-18 (mobile code), SI-10 (input validation), AC-4 (information
# flow enforcement), SI-15 (output filtering).
RSpec.describe "User-content download disposition (#894)", type: :request do
  let(:user) { create(:user) }

  def evidence_with_file(filename: "policy.pdf", content_type: "application/pdf")
    create(:evidence).tap do |e|
      e.file.attach(io: StringIO.new("BYTES"), filename: filename, content_type: content_type)
      e.compute_file_hash! # mints the initial artifact version (#680)
    end
  end

  describe "the emitted signed URL" do
    before { sign_in_as(user) }

    it "carries disposition=attachment for an artifact" do
      evidence = evidence_with_file
      get artifact_path(uuid: evidence.uuid)

      expect(response).to have_http_status(:found)
      expect(response.location).to include("disposition=attachment")
      expect(response.location).not_to include("disposition=inline")
    end

    it "carries disposition=attachment for a retained version" do
      evidence = evidence_with_file
      version  = evidence.current_artifact_version

      get artifact_version_path(uuid: version.uuid)

      expect(response).to have_http_status(:found)
      expect(response.location).to include("disposition=attachment")
      expect(response.location).not_to include("disposition=inline")
    end

    # The upload types that would actually execute if served inline. An
    # attachment disposition has to hold regardless of what was uploaded.
    [
      [ "evil.html", "text/html" ],
      [ "evil.svg",  "image/svg+xml" ],
      [ "evil.xhtml", "application/xhtml+xml" ]
    ].each do |filename, content_type|
      it "still forces attachment for #{content_type}" do
        evidence = evidence_with_file(filename: filename, content_type: content_type)

        get artifact_path(uuid: evidence.uuid)

        expect(response.location).to include("disposition=attachment")
        expect(response.location).not_to include("disposition=inline")
      end
    end
  end

  # A source-level scan, because the runtime assertions above only cover the
  # resolver. This catches someone adding `disposition: "inline"` to a NEW
  # user-content path, which is the actual failure mode: omission is safe
  # (Rails defaults to attachment), an explicit "inline" is not.
  describe "no user-content path serves inline" do
    # help_controller serves APP-SHIPPED user-guide imagery from
    # UserGuideLibrary.image_path — repo content, not user uploads — and inline
    # is correct there. Allowlisted BY NAME so that adding to this list is a
    # deliberate act rather than a suppression. It also carries a Brakeman
    # ignore entry for the same call (config/brakeman.ignore).
    ALLOWED_INLINE = {
      "app/controllers/help_controller.rb" =>
        "app-shipped user-guide images (UserGuideLibrary), not user uploads"
    }.freeze

    it "finds inline dispositions only in the allowlisted files" do
      offenders = Dir.glob(Rails.root.join("app/controllers/**/*.rb")).filter_map do |path|
        relative = Pathname.new(path).relative_path_from(Rails.root).to_s
        next if ALLOWED_INLINE.key?(relative)

        File.read(path).match?(/disposition:\s*["']inline["']/) ? relative : nil
      end

      expect(offenders).to be_empty,
        "These controllers serve content inline. If the bytes are user-supplied that is a " \
        "stored-XSS vector; if they are app-shipped, add them to ALLOWED_INLINE with a reason.\n" \
        "  #{offenders.join("\n  ")}"
    end

    it "keeps the allowlist honest — every entry still exists and still serves inline" do
      ALLOWED_INLINE.each_key do |relative|
        path = Rails.root.join(relative)
        expect(path).to exist, "#{relative} is allowlisted but no longer exists — drop the entry"
        expect(File.read(path)).to match(/disposition:\s*["']inline["']/),
          "#{relative} no longer serves inline — drop the entry so the allowlist cannot rot"
      end
    end
  end

  # The second layer #515 relies on, protected until now only by prose in
  # config/initializers/session_store.rb. Adding `domain:` there would broaden
  # the cookie to every subdomain (RFC 6265 §5.1.3) — the exact opposite of the
  # intent, and it would defeat the cookieless-blob-host protection. PR #530
  # caught this during planning; this catches it during CI.
  describe "session cookie stays host-only" do
    it "sets no Domain= attribute" do
      get login_path

      set_cookie = Array(response.headers["Set-Cookie"]).join("\n")
      expect(set_cookie).not_to match(/;\s*domain=/i),
        "The session cookie gained a Domain= attribute, which sends it to every subdomain " \
        "including the userdata blob host (#515). See config/initializers/session_store.rb."
    end

    it "does not configure a session cookie domain" do
      expect(Rails.application.config.session_options[:domain]).to be_nil
    end
  end
end
