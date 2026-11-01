# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf — the colours are the product's (owner, 2026-10-31: "the colors are
# copyright pending and need to stay as the CSS colors from main"). The new
# navigation changes layout, never colour: every button a screen draws keeps
# the sparc-action intent and variant the same button has on main.
#
# Main's look is spec/fixtures/main_look.yml, recorded from the switched-off
# view before #1297 removed it. Buttons are matched by label within the page
# body (not the top bar); a button main does not draw is not compared.
RSpec.describe "Button colours match main", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:boundary) { create(:authorization_boundary, name: "Colour ATO") }

  # The fixture's document screens, keyed as it keys them.
  def documents
    ssp = create(:ssp_document, authorization_boundary: boundary, status: "completed", lifecycle_status: "in_progress")
    create(:ssp_control, ssp_document: ssp, control_id: "ac-1")
    { "ssp" => ssp,
      "sap" => create(:sap_document, authorization_boundary: boundary, status: "completed"),
      "sar" => create(:sar_document, authorization_boundary: boundary, status: "completed"),
      "poam" => create(:poam_document, authorization_boundary: boundary, status: "completed"),
      "cdef" => create(:cdef_document, status: "completed"),
      "profile" => create(:profile_document, status: "completed"),
      "catalog" => create(:control_catalog, status: "completed", lifecycle_status: "in_progress"),
      "evidence" => create(:evidence, authorization_boundary: boundary) }
  end

  def main_look = YAML.load_file(Rails.root.join("spec/fixtures/main_look.yml")).fetch("button_colours")

  def lists = %w[
    /ssp_documents /sap_documents /sar_documents /poam_documents /profile_documents /cdef_documents /control_catalogs
    /evidences /control_mappings /converters /review_queue /promotion_queue /federation_peers /authoritative_sources
    /leveraged_poam_documents /admin/users /admin/roles /admin/service_accounts /admin/organizations
    /admin/authorization_boundaries /admin/remediation_timelines /admin/audit_logs /admin/idp_grants
    /admin/data_migrations /admin/reconciliation /
  ]

  # Buttons the new navigation renamed: its label => the label on main.
  def renamed = {
    "New user" => "New User", "New role" => "New Role", "New organization" => "New Organization",
    "New boundary" => "New Auth Boundary", "Rename" => "Edit"
  }

  # Buttons only the new navigation draws, held to the look the same control
  # has on main: the folded "More actions" menu is main's "More" menu
  # (authorization_boundaries/_more_menu).
  def main_looks = { "More actions" => [ "sparc-action--neutral sparc-action--outline" ] }

  # label => [the button's sparc-action intent/variant classes, ...]
  def buttons(path)
    get path
    follow_redirect! while response.redirect?
    page = Nokogiri::HTML(response.body)
    body = page.at_css(".sparc-main-content > .container") || page.at_css("body > .container")
    body.css("a.sparc-action, button.sparc-action, input.sparc-action").each_with_object({}) do |el, found|
      label = (el.text.presence || el["value"]).to_s.squish.sub(/\A[←＋+↑✨✎]\s*/, "")
      next if label.empty?

      (found[label] ||= []) << el["class"].split.grep(/\Asparc-action--/).reject { _1 == "sparc-action--sm" }.sort.join(" ")
    end
  end

  before do
    allow(SparcConfig).to receive_messages(any_auth_enabled?: true, aws_labs_cdef_enabled?: true)
    sign_in_as(admin)
  end

  it "draws every shared button in main's colours on every screen" do
    screens = lists.to_h { [ _1, _1 ] }.merge("boundary" => authorization_boundary_path(boundary))
                   .merge(documents.transform_values { polymorphic_path(_1) })
    expect(screens.keys).to match_array(main_look.keys)
    compared = 0
    drift = screens.flat_map do |key, path|
      main = main_look.fetch(key)
      buttons(path).filter_map do |label, looks|
        main_label = renamed.fetch(label, label)
        expected = main[main_label] || main_looks[label]
        next unless expected

        compared += 1
        "#{key} #{label}: main #{expected.uniq} now #{looks.uniq}" unless expected.uniq.sort == looks.uniq.sort
      end
    end

    expect(drift).to be_empty, -> { "buttons drawn in other colours than main:\n  #{drift.join("\n  ")}" }
    expect(compared).to be >= 90
  end
end
