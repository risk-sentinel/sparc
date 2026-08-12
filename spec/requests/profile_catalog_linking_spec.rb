# frozen_string_literal: true

require "rails_helper"

# #928 — an imported profile that is not linked to a catalog is permanently
# unpublishable, and had no UI route to a catalog.
#
# #911 shipped a picker, but only inside the reconciliation banner, which
# renders only while the document BLOCKS updates. Two reachable states fall
# outside that:
#
#   A. a profile that references no controls yet — `lineage_issues` is empty by
#      design ("nothing to trace"), so no banner, so no picker. `Manage
#      Controls` and the publish button are ALSO hidden without a catalog, so
#      the screen dead-ends completely.
#   B. a profile already linked to the WRONG catalog — reconciled, banner gone,
#      and the only remaining remedy was `PATCH /api/v1/profile_documents/:id`.
#
# Both are produced by the ordinary import order: upload a baseline before
# loading the catalog it derives from.
RSpec.describe "Linking a profile to its source catalog", type: :request do
  let(:catalog)     { create(:control_catalog, name: "NIST 800-53 Rev 5 HIGH") }
  let(:other_catalog) { create(:control_catalog, name: "NIST 800-53 Rev 4 MODERATE") }
  let(:user)        { create(:user) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(user)
    grant_permission(user, "profiles.write")
  end

  # State A — the one with no banner at all.
  describe "an imported profile with no controls and no catalog" do
    let(:profile) do
      create(:profile_document, control_catalog: nil,
                                import_metadata: { "format" => "oscal_profile" })
    end

    it "has nothing to reconcile, so the banner does not carry the remedy" do
      # This is the premise of the bug, asserted rather than assumed: if this
      # ever starts blocking, the banner covers the case and the durable picker
      # below is redundant.
      expect(profile.references_controls?).to be(false)
      expect(profile.reconciliation).to be_nil
      expect(profile.reconciliation_blocks_update?).to be(false)
    end

    it "offers a catalog picker on the profile screen" do
      # `catalog` is referenced deliberately, not incidentally: the picker can
      # only offer catalogs that EXIST, and without this the example passed
      # locally (where the test database carries seeded catalogs) and failed in
      # CI (where the table is empty) — blaming the picker for fixture state.
      catalog

      get profile_document_path(profile)

      expect(response.body).to include("No source catalog is linked")
      expect(response.body).to include("profile_document[control_catalog_id]")
      expect(response.body).to include(set_baseline_profile_document_path(profile))
      expect(response.body).to include("Link catalog")
    end

    it "says so plainly when there is no catalog to choose, rather than offering an empty picker" do
      # The behaviour the CI failure exposed, now pinned rather than depended
      # upon. SPARC never synthesises a baseline from the document's own
      # controls — that would check the document against itself — so with
      # nothing loaded the honest answer is to name the remedy.
      #
      # "No catalog is loaded" is stated at the seam rather than by emptying the
      # table. CI's table already is empty; a local one carries seeded catalogs,
      # and an example that only holds in one of the two is exactly how the bug
      # above got through. Deleting them is not an option either — three
      # separate tables hold foreign keys to `control_catalogs`, and chasing
      # them by hand means this spec breaks the next time a fourth is added.
      #
      # `CatalogLineage#choosable` reads `ControlCatalog.all`, so that is the
      # condition under test. Everything downstream of it — the view, the
      # partial, the branch — still runs for real.
      allow(ControlCatalog).to receive(:all).and_return(ControlCatalog.none)

      get profile_document_path(profile)

      expect(response.body).to include("No control catalog is loaded to choose from")
      expect(response.body).not_to include("profile_document[control_catalog_id]")
    end

    it "names the missing catalog in the header, not only in the picker" do
      get profile_document_path(profile)

      expect(response.body).to include("No source catalog")
    end

    it "links the catalog through set_baseline" do
      patch set_baseline_profile_document_path(profile),
            params: { profile_document: { control_catalog_id: catalog.id } }

      expect(profile.reload.control_catalog).to eq(catalog)
    end

    it "records who linked it" do
      expect {
        patch set_baseline_profile_document_path(profile),
              params: { profile_document: { control_catalog_id: catalog.id } }
      }.to change { AuditEvent.where(action: "profile_document_baseline_declared").count }.by(1)
    end
  end

  # The acceptance criterion that matters: the profile is no longer stuck.
  describe "after linking, the normal flow reopens" do
    # Publication has three independent gates — OSCAL metadata, content
    # completeness (#627) and the catalog link. Only the third is what #928 is
    # about, so the other two are satisfied here; otherwise this example would
    # pass or fail for reasons that have nothing to do with the fix.
    let(:valid_metadata) do
      party_uuid = SecureRandom.uuid
      {
        "roles" => [ { "id" => "prepared-by", "title" => "Prepared By" } ],
        "parties" => [ { "uuid" => party_uuid, "type" => "organization", "name" => "Test Org" } ],
        "responsible-parties" => [ { "role-id" => "prepared-by", "party-uuids" => [ party_uuid ] } ]
      }
    end

    before { allow(SparcConfig).to receive(:require_document_approval?).and_return(false) }

    let(:profile) do
      create(:profile_document, control_catalog: nil, metadata_extra: valid_metadata,
                                import_metadata: { "format" => "oscal_profile" }).tap do |doc|
        create(:profile_control, profile_document: doc, control_id: "ac-1", priority: "P1")
      end
    end

    it "publishes, where before it could not" do
      # Before: every other gate satisfied, and it is STILL refused — on the
      # catalog link specifically. That specificity is the point.
      patch publish_profile_document_path(profile)
      expect(profile.reload).not_to be_published_lifecycle
      follow_redirect!
      expect(response.body).to include("no source catalog linked")

      patch set_baseline_profile_document_path(profile),
            params: { profile_document: { control_catalog_id: catalog.id } }
      patch publish_profile_document_path(profile)

      expect(profile.reload).to be_published_lifecycle
    end

    # Linking is necessary, not sufficient — and the fix must not be read as
    # "linking a catalog makes anything publishable". #627 gates publication on
    # content-completeness separately, so an empty profile stays unpublishable
    # after linking, for a different and correct reason.
    it "does not make an empty profile publishable" do
      empty = create(:profile_document, control_catalog: catalog, metadata_extra: valid_metadata)

      patch publish_profile_document_path(empty)

      expect(empty.reload).not_to be_published_lifecycle
      expect(empty.content_complete?).to be(false)
    end

    it "exposes Manage Controls, which is hidden while unlinked" do
      get profile_document_path(profile)
      expect(response.body).not_to include(manage_controls_profile_document_path(profile))

      profile.update!(control_catalog: catalog)

      get profile_document_path(profile)
      expect(response.body).to include(manage_controls_profile_document_path(profile))
    end
  end

  # State B — reconciled, so #911's banner is gone.
  describe "a profile linked to the wrong catalog" do
    let(:profile) do
      create(:profile_document, control_catalog: catalog).tap do |doc|
        create(:profile_control, profile_document: doc, control_id: "ac-1")
      end
    end

    it "is reconciled, so the banner offers nothing" do
      expect(profile.reconciliation_blocks_update?).to be(false)
      get profile_document_path(profile)
      expect(response.body).not_to include("Baseline not set")
    end

    it "still offers the picker, pre-selected with the current catalog" do
      get profile_document_path(profile)

      expect(response.body).to include("Change catalog")
      expect(response.body).to match(/<option selected[^>]*value="#{catalog.id}"/)
    end

    it "re-points to a different catalog while in draft" do
      patch set_baseline_profile_document_path(profile),
            params: { profile_document: { control_catalog_id: other_catalog.id } }

      expect(profile.reload.control_catalog).to eq(other_catalog)
    end
  end

  # The guard #928 makes reachable: before this, a published document had no
  # route to set_baseline, because the only picker lived in a banner that a
  # publishable document never showed.
  describe "a published profile" do
    let(:profile) do
      create(:profile_document, control_catalog: catalog, lifecycle_status: "published")
    end

    it "refuses to be re-pointed at a different catalog" do
      patch set_baseline_profile_document_path(profile),
            params: { profile_document: { control_catalog_id: other_catalog.id } }

      expect(profile.reload.control_catalog).to eq(catalog)
      follow_redirect!
      expect(response.body).to include("published and its baseline is fixed")
    end

    it "does not draw the picker" do
      get profile_document_path(profile)

      expect(response.body).not_to include("Change catalog")
    end

    # The trap #911 exists to avoid: a document published BEFORE lineage
    # shipped is both published and unreconciled. Blocking set_baseline on
    # published documents wholesale would make those permanently unreconcilable.
    it "may still declare a baseline it never had" do
      legacy = create(:profile_document, control_catalog: nil, lifecycle_status: "published")

      patch set_baseline_profile_document_path(legacy),
            params: { profile_document: { control_catalog_id: catalog.id } }

      expect(legacy.reload.control_catalog).to eq(catalog)
    end
  end

  # #919's lesson: a rule the UI enforces and the API does not is not a rule.
  # `profile_params` has always permitted `control_catalog_id` on update, so
  # without this the web guard above is only a speed bump.
  describe "the API agrees with the web" do
    let(:token) { ApiToken.generate!(user: user, name: "Profile linking test") }
    let(:headers) { { "Authorization" => "Bearer #{token.plaintext_token}" } }

    it "links a catalog on a draft profile" do
      profile = create(:profile_document, control_catalog: nil)

      patch api_v1_profile_document_path(profile),
            params: { profile_document: { control_catalog_id: catalog.id } },
            headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(profile.reload.control_catalog).to eq(catalog)
    end

    it "refuses to repoint a published profile" do
      profile = create(:profile_document, control_catalog: catalog, lifecycle_status: "published")

      patch api_v1_profile_document_path(profile),
            params: { profile_document: { control_catalog_id: other_catalog.id } },
            headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(profile.reload.control_catalog).to eq(catalog)
    end

    it "still lets a published legacy profile declare a catalog it never had" do
      legacy = create(:profile_document, control_catalog: nil, lifecycle_status: "published")

      patch api_v1_profile_document_path(legacy),
            params: { profile_document: { control_catalog_id: catalog.id } },
            headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(legacy.reload.control_catalog).to eq(catalog)
    end
  end

  describe "a user without profiles.write" do
    let(:reader) { create(:user) }
    let(:profile) { create(:profile_document, control_catalog: nil) }

    before { sign_in_as(reader) }

    it "is not offered a picker it could not use" do
      get profile_document_path(profile)

      expect(response.body).not_to include("Link catalog")
    end

    it "is refused the write" do
      patch set_baseline_profile_document_path(profile),
            params: { profile_document: { control_catalog_id: catalog.id } }

      expect(profile.reload.control_catalog).to be_nil
    end
  end
end
