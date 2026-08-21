# User Guides API (#784) — read-only access to the in-app help content.
#
# Backs the in-app Help Center (HelpController is a thin HTML client of the same
# UserGuideLibrary service) and lets integrators pull the shipped documentation
# programmatically. Content is the wiki User Guides bundled in the image, so it
# is versioned with the deployment.
#
# NIST SP 800-53: N/A — ships public product documentation; no record data.
class Api::V1::GuidesController < Api::V1::BaseController
  # GET /api/v1/guides — list all guides (slug, title, summary).
  def index
    rows = UserGuideLibrary.all.map { |g| { slug: g.slug, title: g.title, summary: g.summary } }
    render json: { data: rows, meta: whole_collection(rows) }
  end

  # GET /api/v1/guides/:slug — a single guide with rendered HTML.
  def show
    guide = UserGuideLibrary.find(params[:slug])
    return render json: { error: "Not found" }, status: :not_found unless guide

    render json: {
      slug: guide.slug,
      title: guide.title,
      summary: guide.summary,
      html: guide.html
    }
  end
end
