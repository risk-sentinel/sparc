# frozen_string_literal: true

require "rails_helper"

# #1252 — the baseline page says what it could not apply and what it tailors:
# selectors an unlinked import needs its catalog for, ids the catalog lacks,
# and each control's removes and added parts.
RSpec.describe "Profile selection on the baseline page (#1252)", type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(admin)
  end

  def page_for(profile)
    get profile_document_path(profile)
    Nokogiri::HTML(response.body)
  end

  it "names the selectors an unlinked import could not apply" do
    profile = create(:profile_document, import_metadata: {
      "unlinked_imports" => [ { "href" => "#x", "title" => "Org Controls", "control_ids" => [],
                                "unresolved_selectors" => %w[include-all matching] } ]
    })

    text = page_for(profile).at_css("[data-testid='unresolved-selectors']")&.text.to_s
    expect(text).to include("include-all, matching")
  end

  it "lists the ids a linked import names that its catalog does not have" do
    profile = create(:profile_document, import_metadata: {
      "imports" => [ { "href" => "#x", "title" => "NIST", "catalog_id" => 1, "unknown_ids" => %w[zz-99] } ]
    })

    expect(page_for(profile).at_css("[data-testid='unknown-control-ids']")&.text.to_s).to include("zz-99")
  end

  it "shows neither warning when every import linked and every id is known" do
    profile = create(:profile_document, import_metadata: { "imports" => [ { "href" => "#x", "catalog_id" => 1 } ] })
    page = page_for(profile)

    expect(page.at_css("[data-testid='unknown-control-ids']")).to be_nil
    expect(page.at_css("[data-testid='unresolved-selectors']")).to be_nil
  end

  it "shows what the baseline removes from and adds to a control" do
    profile = create(:profile_document)
    profile.profile_controls.create!(control_id: "zz-1", row_order: 0, alters: [ {
      "removes" => [ { "by-id" => "zz-1_smt.b" } ],
      "adds" => [ { "position" => "after", "by-id" => "zz-1_smt.a",
                    "parts" => [ { "id" => "zz-1_smt.c", "name" => "item", "prose" => "Brief staff annually." } ] } ]
    } ])

    block = page_for(profile).at_css("[data-testid='profile-control-alters']")
    expect(block).to be_present
    expect(block.at_css("[data-testid='alter-remove']").text).to eq("by-id=zz-1_smt.b")
    expect(block.at_css("[data-testid='alter-add']").text.squish).to include("zz-1_smt.c", "after zz-1_smt.a", "Brief staff annually.")
  end

  it "shows no tailoring block for a control the baseline does not alter" do
    profile = create(:profile_document)
    profile.profile_controls.create!(control_id: "zz-1", row_order: 0)

    expect(page_for(profile).at_css("[data-testid='profile-control-alters']")).to be_nil
  end
end
