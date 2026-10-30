# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1296 / #1297 — nothing reachable before the refactor becomes
# unreachable in the shell.
#
# Phase 0 recorded what each viewer's header and sidebar offered
# (tests/ui-smoke/nav_inventory.json). The shell moves those links — into the
# header's menus, the tab bars, the switcher, the Overview and the boundary's
# own page — so this compares PATHS, not places, in both directions:
#
#   * every recorded path is still a link somewhere on the viewer's home page
#     or boundary page, unless it is in REMOVED (a link the old menus showed to
#     someone its screen refuses);
#   * every path the shell's NAVIGATION offers (header and tab bar) was
#     recorded, or is in `added` — a deliberate, reviewed addition.
#
# The classic header with the switch off is pinned by nav_inventory_spec.rb.
#
# NIST SP 800-53 Rev 5: AC-3, AC-6 (a viewer is offered only what they may open).
RSpec.describe "Shell navigation inventory (1.18.0-rf #1296)", type: :request do
  let(:org) { create(:organization, name: "Example Agency") }
  let!(:mine) { create(:authorization_boundary, name: "Mine System", organization: org, status: "active") }
  let!(:theirs) { create(:authorization_boundary, name: "Theirs System", organization: org) }

  let(:member) do
    create(:user).tap do |u|
      create(:organization_membership, user: u, organization: org)
      grant_permission(u, "authorization_boundaries.read", authorization_boundary: mine)
    end
  end
  let(:admin) { create(:user, :admin) }

  # Links the classic menus showed to viewers whose screen refuses them. The
  # shell shows each exactly when its screen admits the viewer.
  def removed = {
    # AuthoritativeSourcesController#authorize_read! needs back_matter.read;
    # HdfTriageController#authorize_read! needs evidence.read on the boundary.
    "signed_in_member" => [ "/authoritative_sources", "/authorization_boundaries/:boundary/triage" ]
  }

  # Deliberate additions in the shell's navigation, per viewer, each behind
  # the predicate its screen enforces.
  def create_paths = %w[/cdef_documents/new /evidences/new /poam_documents/new /profile_documents/new
              /sap_documents/new /sar_documents/new /ssp_documents/new]
  def create_in_boundary = %w[evidences poam_documents sap_documents sar_documents ssp_documents]
                       .map { "/#{_1}/new?authorization_boundary_id=:boundary" }
  # Phase 2's boundary tab bar: the document lists narrowed to the boundary.
  def boundary_tabs = %w[cdef_documents evidences leveraged_poam_documents poam_documents sap_documents
                     sar_documents ssp_documents].map { "/#{_1}?authorization_boundary_id=:boundary" }
  def added = {
    # The Leveraged POA&Ms boundary tab (phase 2).
    "signed_in_member" => [ "/leveraged_poam_documents?authorization_boundary_id=:boundary" ],
    # #1295 Create menu, the review queue (an administrator approves every
    # reviewable type), and the Leveraged POA&Ms boundary tab.
    "signed_in_admin" => create_paths + create_in_boundary + [ "/review_queue",
                                                          "/leveraged_poam_documents?authorization_boundary_id=:boundary" ],
    # With sign-in disabled there was no sidebar (phase 0 found the gap), so the
    # library, help and reference links, the boundaries and their tabs, and
    # Settings (admin_access? admits everyone) are new here; so is Create.
    "auth_disabled" => create_paths + create_in_boundary + boundary_tabs + %w[
      /admin/organizations /authorization_boundaries/:boundary /federation_peers /help
      /leveraged_poam_documents /promotion_queue
    ] + Array(SparcConfig.resources).map { _1["href"] }
  }

  def shell_pages(posture)
    pages = posture[:pages].map { public_send(NavInventory::PAGE_PATHS.fetch(_1)) }
    pages << authorization_boundary_path(mine) if posture[:user] || !posture[:auth]
    pages
  end

  def normalize(href)
    NavInventory.normalize_path(href).sub(%r{\A/profile_documents/\d+}, "/profile_documents/:id")
  end

  def links(doc, scope)
    doc.css("#{scope} a[href], #{scope} form[action]").filter_map do |el|
      href = el.name == "form" ? el["action"] : el["href"]
      normalize(href) unless href.blank? || href.start_with?("#")
    end
  end

  def shell_for(posture)
    allow(SparcConfig).to receive_messages(any_auth_enabled?: posture[:auth], enable_local_login?: posture[:auth],
                                           public_catalogs?: posture[:public], fido2_enabled?: true, nav_shell?: true)
    sign_in_as(public_send(posture[:user])) if posture[:user]

    shell_pages(posture).each_with_object({ reach: Set.new, nav: Set.new }) do |path, acc|
      get path
      expect(response).to have_http_status(:ok), "#{path} returned #{response.status}"
      doc = Nokogiri::HTML(response.body)
      acc[:reach].merge(links(doc, "body"))
      acc[:nav].merge(links(doc, "[data-testid=shell-header]") + links(doc, "[data-testid=shell-bar]"))
    end
  end

  NavInventory::POSTURES.each do |name, posture|
    it "keeps every link the #{name} viewer had, and adds only what was reviewed" do
      recorded = NavInventory.load.fetch("postures").fetch(name).map { _1["path"] }.to_set
      offered = shell_for(posture)

      lost = recorded - offered[:reach] - removed.fetch(name, [])
      extra = offered[:nav] - recorded - added.fetch(name, [])
      expect(lost).to be_empty, "#{name}: no longer reachable in the shell:\n  #{lost.to_a.sort.join("\n  ")}"
      expect(extra).to be_empty, "#{name}: offered by the shell but not reviewed:\n  #{extra.to_a.sort.join("\n  ")}"
    end

    it "never offers the #{name} viewer a path it removed" do
      offered = shell_for(posture)
      expect(offered[:nav] & removed.fetch(name, []).to_set).to be_empty
    end
  end
end
