# frozen_string_literal: true

# 1.18.0-rf — what SPARC's navigation offered each viewer on v1.17.5, before the
# navigation refactor (#1286), and how a path is compared with it.
#
# `tests/ui-smoke/nav_inventory.json` was recorded from the classic header and
# sidebar in phase 0, before any navigation code changed. It is fixed history:
# #1297 removed that header, and the promise it records is checked against the
# new one — spec/requests/shell_nav_inventory_spec.rb (the rendered HTML, every
# posture) and tests/ui-smoke/test_nav_regression_1307.py (clicked in Chrome),
# which applies the same normalisation (tests/ui-smoke/nav_inventory_paths.py).
#
# An entry is { menu, label, path }; the path has record-specific parts replaced
# by placeholders, so the inventory describes navigation rather than one
# database:
#   /authorization_boundaries/<slug>   -> /authorization_boundaries/:boundary
#   ?authorization_boundary_id=<id>    -> ?authorization_boundary_id=:boundary
#   /help/<slug>                       -> /help/:guide
module NavInventory
  extend self

  FIXTURE = Rails.root.join("tests/ui-smoke/nav_inventory.json")

  BOUNDARY = ":boundary"

  # Each posture: how the instance is configured, who is looking (a `let` in
  # the spec), and which pages to read the navigation from. The signed-out
  # postures read the sign-in page, which is where an anonymous visitor lands,
  # and (when the library is public) a public page too.
  POSTURES = {
    "signed_out" => { auth: true, public: false, user: nil, pages: %i[login] },
    "signed_out_public_catalogs" => { auth: true, public: true, user: nil, pages: %i[login catalogs] },
    "auth_disabled" => { auth: false, public: false, user: nil, pages: %i[home] },
    "signed_in_member" => { auth: true, public: false, user: :member, pages: %i[home] },
    "signed_in_admin" => { auth: true, public: false, user: :admin, pages: %i[home] }
  }.freeze

  PAGE_PATHS = { login: :login_path, catalogs: :control_catalogs_path, home: :root_path }.freeze

  def normalize_path(href)
    return href if href.to_s.match?(%r{\Ahttps?://})

    uri = URI.parse(href)
    path = uri.path
               .sub(%r{\A/authorization_boundaries/[^/]+}, "/authorization_boundaries/#{BOUNDARY}")
               .sub(%r{\A/help/[^/]+\z}, "/help/:guide")
    return path if uri.query.blank?

    query = Rack::Utils.parse_query(uri.query)
    query[BoundaryScopedList::PARAM.to_s] = BOUNDARY if query.key?(BoundaryScopedList::PARAM.to_s)
    "#{path}?#{query.sort.map { |k, v| "#{k}=#{v}" }.join('&')}"
  end

  def load
    JSON.parse(FIXTURE.read)
  end
end
