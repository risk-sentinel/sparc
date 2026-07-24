# In-app Help Center (#784) — renders the bundled User Guides as job aids.
#
# Thin HTML client of UserGuideLibrary (the same service backs Api::V1::Guides).
# Content is the wiki User Guides shipped in the image, so it is offline-capable
# and versioned with the deployment.
#
# NIST SP 800-53: N/A — informational pages; no security-critical logic.
class HelpController < ApplicationController
  # Guide images are static doc assets; skip the password-reset gate so a
  # freshly-seeded admin can still load screenshots (they render inside pages
  # the gate already allows once cleared, but the image subrequests must not
  # themselves bounce to /password/edit).
  skip_before_action :check_password_reset, only: [ :image ], raise: false

  # GET /help — searchable index of all guides.
  def index
    @guides = UserGuideLibrary.all
  end

  # GET /help/:slug — a single rendered guide.
  def show
    @guide = UserGuideLibrary.find(params[:slug])
    # not_found renders 404, which suppresses the implicit show render.
    not_found unless @guide
  end

  # GET /help/images/:filename — serve a guide screenshot from wiki/images.
  # Path is constrained by the service (no traversal, basename only).
  def image
    path = UserGuideLibrary.image_path(params[:filename])
    return head :not_found unless path

    send_file path,
              type: Mime::Type.lookup_by_extension(File.extname(path).delete(".")) || "application/octet-stream",
              disposition: "inline",
              # Immutable per deploy — the file changes only when the image ships.
              url_based_filename: true
    response.set_header("Cache-Control", "public, max-age=3600")
  end

  private

  def not_found
    render file: Rails.root.join("public/404.html"), status: :not_found, layout: false
  end
end
