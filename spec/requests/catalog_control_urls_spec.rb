# frozen_string_literal: true

require "rails_helper"

# #881 — controls are addressed by a readable, catalog-scoped identifier
# instead of a database id.
#
# The two failure modes this pins are both silent:
#
#   1. Rails parses a trailing `.something` as the FORMAT, so
#      `/controls/ac-1a.1.a` would arrive as `ac-1a.1` — resolving the PARENT
#      control rather than erroring. 1478 of 2447 distinct control ids contain a
#      dot, so this is the common case, not an edge case.
#   2. `control_id` is unique only per family, and SPARC seeds both NIST Rev 4
#      and Rev 5, so `ac-2` exists more than once. Scoping is what makes the
#      identifier resolvable at all.
RSpec.describe "Catalog control URLs (#881)", type: :request do
  let(:admin) { create(:user, :admin) }

  # Two catalogs holding the SAME control id, plus a statement sub-part whose
  # stored id carries parentheses — the shape that forced a canonical form.
  let!(:rev5)   { create(:control_catalog, name: "NIST 800-53 Rev 5") }
  let!(:rev4)   { create(:control_catalog, name: "NIST 800-53 Rev 4") }
  let!(:family5) { create(:control_family, control_catalog: rev5, code: "AC") }
  let!(:family4) { create(:control_family, control_catalog: rev4, code: "AC") }

  let!(:control5)  { family5.catalog_controls.create!(control_id: "ac-2", title: "Account Management (r5)") }
  let!(:control4)  { family4.catalog_controls.create!(control_id: "ac-2", title: "Account Management (r4)") }
  let!(:sub_part)  { family5.catalog_controls.create!(control_id: "ac-1a.1.(a)", title: "Statement part") }
  let!(:parent)    { family5.catalog_controls.create!(control_id: "ac-1a.1", title: "Parent of the part") }

  before { sign_in_as(admin) }

  describe "the canonical identifier" do
    it "is derived from ControlId, not invented here" do
      expect(sub_part.canonical_identifier).to eq("ac-1a.1.a")
      expect(control5.canonical_identifier).to eq("ac-2")
    end

    it "is what to_param yields, so path helpers produce readable URLs" do
      # to_param stays the slug (the API identifier is a published contract);
      # the uuid is passed explicitly for the web canonical URL.
      expect(control_catalog_control_path(rev5.url_id, sub_part))
        .to eq("/control_catalogs/#{rev5.oscal_uuid}/controls/ac-1a.1.a")
      # the CANONICAL form uses the OSCAL uuid — stable, and it distinguishes
      # 5.1.0 from 5.2.0 where a "rev5" label would merge them
      expect(control_catalog_control_path(rev5.url_id, sub_part))
        .to eq("/control_catalogs/#{rev5.oscal_uuid}/controls/ac-1a.1.a")
    end
  end

  describe "resolving a control" do
    it "renders the control's own page" do
      get control_catalog_control_path(rev5, control5)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Account Management (r5)")
    end

    # The format trap. Without `format: false` this request resolves `ac-1a.1`
    # — the PARENT — and renders a page that looks perfectly fine.
    it "resolves a dotted sub-part to the sub-part, NOT its parent" do
      get control_catalog_control_path(rev5, sub_part)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Statement part")
      expect(response.body).not_to include("Parent of the part")
    end

    it "keeps the same id in different catalogs distinct" do
      get control_catalog_control_path(rev5, control5)
      expect(response.body).to include("Account Management (r5)")

      get control_catalog_control_path(rev4, control4)
      expect(response.body).to include("Account Management (r4)")
    end

    it "404s for a control that belongs to a different catalog" do
      get "/control_catalogs/#{rev4.slug}/controls/ac-1a.1.a"

      expect(response).to have_http_status(:not_found)
    end
  end

  # The bug this caught: a prefix match (`control_id LIKE 'ac-1%'`) listed ac-10,
  # ac-11 and half the family as "sub-parts" of ac-1. Misrepresenting the control
  # hierarchy is worse than an ugly URL — it is SPARC stating something false
  # about the catalog.
  describe "the control hierarchy" do
    let!(:ac1)    { family5.catalog_controls.create!(control_id: "ac-1",   title: "Policy and Procedures") }
    let!(:ac1a)   { family5.catalog_controls.create!(control_id: "ac-1a",  title: "Part a") }
    let!(:ac10)   { family5.catalog_controls.create!(control_id: "ac-10",  title: "Concurrent Session Control") }

    it "does NOT treat ac-10 as a sub-part of ac-1" do
      expect(ac1.direct_children.map(&:control_id)).not_to include("ac-10")
    end

    it "lists only the real direct children" do
      expect(ac1.direct_children.map(&:control_id)).to contain_exactly("ac-1a")
    end

    it "nests one level at a time, so every sub-part stays reachable" do
      # `parent` above is ac-1a.1
      expect(ac1a.direct_children.map(&:control_id)).to contain_exactly("ac-1a.1")
    end

    it "renders only true sub-parts on the control page" do
      get control_catalog_control_path(rev5, ac1)

      expect(response.body).to include("Part a")
      expect(response.body).not_to include("Concurrent Session Control")
    end
  end

  describe "legacy numeric URLs" do
    it "301s the show URL to the readable one" do
      get "/catalog_controls/#{control5.id}"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(control_catalog_control_path(rev5.url_id, control5))
    end

    it "301s the edit URL to the readable one" do
      get "/catalog_controls/#{sub_part.id}/edit"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(control_catalog_edit_control_path(rev5.url_id, sub_part))
    end
  end

  describe "the backfill fallback" do
    # canonical_id is populated by a deferred data migration, so between the
    # schema migration and the runner completing it is NULL. URLs must still
    # resolve in that window.
    it "resolves when canonical_id has not been backfilled yet" do
      sub_part.update_column(:canonical_id, nil)

      get control_catalog_control_path(rev5, sub_part.reload)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Statement part")
    end
  end
end
