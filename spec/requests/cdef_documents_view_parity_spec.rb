# frozen_string_literal: true

require "rails_helper"

# #888 §4 — an action offered in one view must be offered in the other.
#
# This is not hypothetical. The card view shipped with no actions at all, and
# because cards are the default, View / Copy / OSCAL export / Delete and the
# bulk-select checkbox all vanished from the screen a user lands on. The full
# suite caught one of the five, by accident, through an unrelated #451 spec.
#
# CdefDocuments is the pilot; each screen #888 migrates gets the same check.
RSpec.describe "CdefDocuments view parity", type: :request do
  let(:admin) { create(:user, :admin) }
  let!(:document) { create(:cdef_document, name: "Parity CDEF", status: "completed") }

  def body_for(view)
    get cdef_documents_path(view: view)
    response.body
  end

  # Each action is identified by a marker that must appear in BOTH views.
  # Matching on the route or the Stimulus hook rather than on button text keeps
  # this about the action being reachable, not about wording. Path helpers only
  # exist on the example instance, so the marker is resolved there.
  ACTIONS = {
    "view" => [ :path, :cdef_document_path ],
    "copy" => [ :path, :copy_cdef_document_path ],
    "oscal export" => [ :literal, 'data-controller="oscal-export"' ],
    "delete" => [ :literal, 'name="_method" value="delete"' ]
  }.freeze

  def marker_for(action)
    kind, value = ACTIONS.fetch(action)
    kind == :path ? send(value, document) : value
  end

  context "as an admin" do
    before { sign_in_as(admin) }

    ACTIONS.each_key do |name|
      it "offers #{name} in both the card and the list view" do
        expected = marker_for(name)

        expect(body_for("card")).to include(expected), "card view is missing #{name}"
        expect(body_for("list")).to include(expected), "list view is missing #{name}"
      end
    end

    it "offers bulk selection in both views" do
      %w[card list].each do |view|
        body = body_for(view)

        expect(body).to include('data-bulk-select-target="row"'), "#{view} view has nothing to select"
        expect(body).to include('data-bulk-select-target="selectAll"'), "#{view} view cannot select all"
        expect(body).to include('form="cdefBulkForm"'), "#{view} view's checkbox is not wired to the bulk form"
      end
    end

    it "shows the same documents in both views" do
      expect(body_for("card")).to include("Parity CDEF")
      expect(body_for("list")).to include("Parity CDEF")
    end
  end

  # The mirror case: an action a signed-out visitor must NOT get has to be
  # absent from both views too. A card that leaks Delete would be the same bug
  # in the other direction.
  #
  # The posture has to be pinned. `can_bulk_delete?` is
  # `!any_auth_enabled? || current_user&.admin?`, so on a deployment with auth
  # switched off every visitor is an admin by design — correct behaviour, and
  # the opposite of what this context is asserting. Leaving it to the ambient
  # environment meant the suite passed locally (auth on) and failed in CI
  # (auth off) while the app was behaving correctly in both.
  context "as an anonymous visitor, with authentication enabled" do
    before do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
      # #974 — an anonymous visitor reaches the CDEF screens only when the
      # control library is published. Before this the controller skipped
      # authentication unconditionally, so this context reached the page in
      # every posture; that was the defect, not the contract. What the context
      # actually tests — that the view withholds destructive actions and keeps
      # the read-only ones — is unchanged and still worth pinning.
      allow(SparcConfig).to receive(:public_catalogs?).and_return(true)
      allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(nil)
      allow_any_instance_of(ApplicationController).to receive(:signed_in?).and_return(false)
    end

    it "withholds destructive actions in both views" do
      %w[card list].each do |view|
        body = body_for(view)

        expect(body).not_to include(copy_cdef_document_path(document)), "#{view} view leaks Copy"
        expect(body).not_to include('data-bulk-select-target="row"'), "#{view} view leaks bulk select"
      end
    end

    it "still offers the read-only actions in both views" do
      %w[card list].each do |view|
        body = body_for(view)

        expect(body).to include(cdef_document_path(document))
        expect(body).to include('data-controller="oscal-export"')
      end
    end
  end

  # The other posture, asserted rather than assumed (#885). With authentication
  # disabled SPARC is a single-user local tool and the visitor IS the admin, so
  # bulk delete is offered — and must be offered in BOTH views, or the default
  # view silently loses it exactly as it did before.
  context "with authentication disabled" do
    before do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(false)
      allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(nil)
      allow_any_instance_of(ApplicationController).to receive(:signed_in?).and_return(false)
    end

    it "offers bulk selection in both views" do
      %w[card list].each do |view|
        expect(body_for(view)).to include('data-bulk-select-target="row"'),
          "#{view} view lost bulk select when auth is disabled"
      end
    end
  end
end
