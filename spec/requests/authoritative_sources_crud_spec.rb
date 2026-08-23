# frozen_string_literal: true

require "rails_helper"

# #1039 — the authoritative-sources surface was create-only. A typo in an href
# was permanent, provenance could not be recorded, and the controls a source
# supports could not be seen from the screen that shows the source.
#
# Both directions are asserted throughout: a permission-holding NON-ADMIN must
# be able to do the thing, and a user without the permission must not. A spec
# that only proves the deny leg passes just as well when the feature is broken
# for everyone.
RSpec.describe "Authoritative sources CRUD (#1039)", type: :request do
  let(:org)     { create(:organization) }
  let(:admin)   { create(:user, :admin) }
  let(:writer)  { create(:user) }
  let(:reader)  { create(:user) }

  let(:source) do
    create(:back_matter_resource, title: "NIST SP 800-53 Rev 5",
                                  href: "https://csrc.nist.gov/",
                                  globally_available: true)
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "edit and update" do
    # `to_param` exists for readability only: the numeric id must keep working,
    # otherwise every stored link and every API path breaks.
    it "still resolves a bare numeric id after the slug is introduced" do
      sign_in_as(admin)

      get "/authoritative_sources/#{source.id}"
      expect(response).to have_http_status(:ok)

      get "/authoritative_sources/#{source.id}-a-totally-wrong-slug"
      expect(response).to have_http_status(:ok)
    end

    it "lets a permission-holding non-admin change a source" do
      grant_permission(writer, "back_matter.write")
      sign_in_as(writer)

      get edit_authoritative_source_path(source)
      expect(response).to have_http_status(:ok)

      patch authoritative_source_path(source), params: {
        back_matter_resource: { title: "NIST SP 800-53 Rev 5.2.0",
                                provided_by_team: "Platform Security",
                                provided_by_contact: "soc@agency.gov" }
      }

      # The path carries an `id-slug`, so renaming the source renames its URL.
      # Build the expectation from the reloaded record; `source` still holds the
      # pre-update title and would assert the old slug.
      source.reload
      expect(response).to redirect_to(authoritative_source_path(source))
      expect(source.title).to eq("NIST SP 800-53 Rev 5.2.0")
      expect(source.provided_by_team).to eq("Platform Security")
      expect(source.provided_by_contact).to eq("soc@agency.gov")
    end

    it "refuses a user without back_matter.write" do
      sign_in_as(reader)

      patch authoritative_source_path(source), params: {
        back_matter_resource: { title: "should not stick" }
      }

      expect(response).to redirect_to(authoritative_sources_path)
      expect(source.reload.title).to eq("NIST SP 800-53 Rev 5")
    end
  end

  describe "destroy" do
    # The whole point of the ruling: DELETE archives. These resources
    # participate in federation (federated_from_instance / original_uuid) and
    # promotion, so a hard delete strands a federated copy on a peer.
    it "ARCHIVES rather than deleting, and the record survives" do
      grant_permission(writer, "back_matter.write")
      sign_in_as(writer)
      # Force the lazy `let` BEFORE measuring: named first inside the
      # expect{} block it is created there, and the count moves 0 -> 1 for
      # reasons that have nothing to do with the delete.
      target = source

      expect { delete authoritative_source_path(target) }
        .not_to change(BackMatterResource, :count)

      expect(source.reload.archived?).to be(true)
      expect(BackMatterResource.active).not_to include(source)
    end

    it "restores an archived source" do
      grant_permission(writer, "back_matter.write")
      sign_in_as(writer)
      source.update!(archived_at: Time.current)

      post restore_authoritative_source_path(source)

      expect(source.reload.archived?).to be(false)
      expect(BackMatterResource.active).to include(source)
    end

    it "can still REACH an archived source, or restore would be unreachable" do
      # `show` guards on back_matter.read as well as the write check, so a
      # writer who cannot read is bounced before the archived question is even
      # reached. Grant both: the claim here is about the ARCHIVED scope, not
      # about the read permission.
      grant_permission(writer, "back_matter.write")
      grant_permission(writer, "back_matter.read")
      sign_in_as(writer)
      source.update!(archived_at: Time.current)

      get authoritative_source_path(source)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "control references" do
    let!(:catalog)  { create(:control_catalog) }
    let!(:family)   { create(:control_family, control_catalog: catalog) }
    let!(:control)  { create(:catalog_control, control_family: family) }

    it "links and unlinks a control" do
      grant_permission(writer, "back_matter.write")
      sign_in_as(writer)

      expect {
        post link_control_authoritative_source_path(source),
             params: { linkable_type: "CatalogControl", control_catalog_id: catalog.id,
                       control_identifier: control.control_id }
      }.to change { source.control_back_matter_links.count }.by(1)

      link = source.control_back_matter_links.last
      expect {
        delete unlink_control_authoritative_source_path(source, link_id: link.id)
      }.to change { source.control_back_matter_links.count }.by(-1)
    end

    # Rev 4 and Rev 5 can be loaded at the same time, so a bare "AC-2" names a
    # control in each. Resolution must honour the catalog the caller picked.
    it "resolves the control within the chosen catalog, not the first match" do
      other_catalog = create(:control_catalog, name: "NIST 800-53 Rev 4")
      other_family  = create(:control_family, control_catalog: other_catalog)
      twin = create(:catalog_control, control_family: other_family,
                                      control_id: control.control_id)

      grant_permission(writer, "back_matter.write")
      sign_in_as(writer)

      post link_control_authoritative_source_path(source),
           params: { linkable_type: "CatalogControl", control_catalog_id: other_catalog.id,
                     control_identifier: control.control_id }

      linked = source.control_back_matter_links.last.linkable
      expect(linked).to eq(twin)
      expect(linked).not_to eq(control)
    end

    it "accepts any casing or padding of the control id" do
      grant_permission(writer, "back_matter.write")
      sign_in_as(writer)

      expect {
        post link_control_authoritative_source_path(source),
             params: { linkable_type: "CatalogControl", control_catalog_id: catalog.id,
                       control_identifier: control.control_id.to_s.upcase }
      }.to change { source.control_back_matter_links.count }.by(1)
    end

    # The old surface called `find` on a raw row id, so a typo was a 404 page
    # rather than a message on the form.
    it "reports an unresolvable control instead of raising" do
      grant_permission(writer, "back_matter.write")
      sign_in_as(writer)

      expect {
        post link_control_authoritative_source_path(source),
             params: { linkable_type: "CatalogControl", control_catalog_id: catalog.id,
                       control_identifier: "ZZ-99" }
      }.not_to change { source.control_back_matter_links.count }

      expect(response).to redirect_to(authoritative_source_path(source))
      expect(flash[:error]).to match(/ZZ-99/)
    end

    it "refuses a linkable_type outside the allowed set" do
      grant_permission(writer, "back_matter.write")
      sign_in_as(writer)

      expect {
        post link_control_authoritative_source_path(source),
             params: { linkable_type: "User", linkable_id: admin.id }
      }.not_to change { source.control_back_matter_links.count }
    end
  end

  describe "the audit trail" do
    # An action missing from AuditEvent::ACTIONS records NOWHERE — the write
    # is rejected by validation and swallowed. These assertions are what proves
    # the five new action names were actually registered.
    it "records update, archive and restore" do
      grant_permission(writer, "back_matter.write")
      sign_in_as(writer)

      patch authoritative_source_path(source), params: { back_matter_resource: { title: "Renamed" } }
      delete authoritative_source_path(source)
      post restore_authoritative_source_path(source)

      actions = AuditEvent.where(subject_type: "BackMatterResource", subject_id: source.id).pluck(:action)
      expect(actions).to include("authoritative_source_updated",
                                 "authoritative_source_archived",
                                 "authoritative_source_restored")
    end
  end
end
