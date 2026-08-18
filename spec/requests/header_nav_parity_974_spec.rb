# frozen_string_literal: true

require "rails_helper"

# #974 — the header banner is ONE definition, and what varies between viewers is
# visibility only.
#
# It used to be hand-copied into `layouts/application` and `layouts/login`, with
# only the environment header and the Controls dropdown extracted. The copies had
# already drifted — the "About" link carried different classes in each — and when
# `SPARC_PUBLIC_CATALOGS` opened component definitions and converters for reading,
# the entries reached one copy and not the other. The login page is where an
# anonymous visitor lands, because `/` redirects there, so the one page that
# needed to advertise the newly-public screens was the one page that did not.
#
# Two properties are asserted here, because either alone permits the bug:
#
#   1. **Parity** — the same viewer sees the same menu on the sign-in page as
#      anywhere else. This is what a shared partial buys, and what a second
#      hand-written copy would silently lose.
#   2. **Reachability** — an entry is shown when the viewer can open it and
#      hidden when they cannot. The banner must never advertise a page that
#      bounces to /login, nor hide one that would open.
#
# Placement is never conditional. SPARC's menus follow the NIST layers and a link
# must be findable in the same spot every time; only its presence varies.
RSpec.describe "Header nav parity (#974)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  # Entries that are reachable without a session ONLY when the library is
  # published, and their menu is the one they natively live in.
  def publicly_readable_entries
    { "Component Definitions" => cdef_documents_path, "Converters" => converters_path }
  end

  # Reachable only with a session, in either posture.
  def session_only_entries
    { "System Security Plans" => ssp_documents_path, "Home" => root_path }
  end

  describe "with SPARC_PUBLIC_CATALOGS=true, anonymously" do
    before { allow(SparcConfig).to receive(:public_catalogs?).and_return(true) }

    it "offers the readable entries on the SIGN-IN page, not only on other pages" do
      get login_path

      publicly_readable_entries.each do |label, path|
        expect(response.body).to include(path),
          "#{label} is readable but the sign-in page does not offer it — the two layouts have drifted"
      end
    end

    it "shows the sign-in page the same entries as any other public page" do
      get login_path
      login_page = response.body

      get control_catalogs_path
      catalog_page = response.body

      (publicly_readable_entries.values + [ control_catalogs_path, about_resources_path ]).each do |path|
        expect(login_page.include?(path)).to eq(catalog_page.include?(path)),
          "#{path} appears on one page and not the other — the banner is not shared"
      end
    end

    it "withholds what an anonymous visitor cannot open, on both pages" do
      [ login_path, control_catalogs_path ].each do |page|
        get page

        session_only_entries.each do |label, path|
          expect(response.body).not_to include("\"#{path}\""),
            "#{label} is advertised on #{page} but would bounce an anonymous visitor to /login"
        end
      end
    end
  end

  describe "with SPARC_PUBLIC_CATALOGS unset, anonymously" do
    before { allow(SparcConfig).to receive(:public_catalogs?).and_return(false) }

    it "offers no Controls-layer entry at all" do
      get login_path

      (publicly_readable_entries.values + [ control_catalogs_path ]).each do |path|
        expect(response.body).not_to include(path),
          "#{path} is advertised while the control library is not published"
      end
    end
  end

  describe "signed in" do
    let(:user) { create(:user, :admin) }

    before do
      allow(SparcConfig).to receive(:public_catalogs?).and_return(false)
      sign_in_as(user)
    end

    # The signed-in experience must be untouched by all of this.
    it "still offers every layer, in its usual menu" do
      get root_path

      [ control_catalogs_path, ssp_documents_path, cdef_documents_path,
        converters_path, sap_documents_path, evidences_path ].each do |path|
        expect(response.body).to include(path), "#{path} vanished from the signed-in header"
      end
    end
  end

  # The structural half: one definition, rendered everywhere.
  it "renders the banner from a single shared partial in every layout" do
    layouts = Rails.root.glob("app/views/layouts/*.html.erb").reject { |p| p.basename.to_s.start_with?("mailer") }

    layouts.each do |layout|
      source = layout.read
      next unless source.include?("navbar")

      expect(source).to include('render "shared/main_nav"'),
        "#{layout.basename} builds its own header instead of rendering shared/main_nav — " \
        "that is how the login page came to advertise a different menu (#974)"
    end
  end
end
