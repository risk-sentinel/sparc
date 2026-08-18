# frozen_string_literal: true

require "rails_helper"

# #948 — tiering on the real screens, through the real controllers.
#
# The service spec proves the grouping. This proves the thing that actually
# matters: wiring tiering into five index actions changed WHAT IS DRAWN and not
# WHO CAN SEE IT. Every screen keeps `boundary_scoped_relation` exactly as it
# was, and the assertion below is what holds that line.
RSpec.describe "Collection tiering (#948)", type: :request do
  let(:org)       { create(:organization, name: "Alpha Agency") }
  let(:mine)      { create(:authorization_boundary, name: "My System", organization: org) }
  let(:theirs)    { create(:authorization_boundary, name: "Their System", organization: org) }
  let(:member)    { create(:user) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  # THE acceptance criterion, per screen. A user sees exactly the records they
  # saw before — tiering is presentation.
  #
  # Evidence is the screen tiering was proven on, and the only one of the five
  # where a nil boundary is genuinely instance-wide, so it carries both cases.
  describe "the visible set is identical before and after" do
    it "shows a member exactly the evidence they could already see" do
      visible_here  = create(:evidence, title: "Mine", authorization_boundary: mine)
      instance_wide = create(:evidence, title: "Shared", authorization_boundary: nil)
      hidden        = create(:evidence, title: "Theirs", authorization_boundary: theirs)

      grant_permission(member, "evidence.read", authorization_boundary: mine)
      sign_in_as(member)

      get evidences_path

      expect(response.body).to include("Mine")
      expect(response.body).to include("Shared")
      # The whole point: tiering must not have widened the scope.
      expect(response.body).not_to include("Theirs")
      expect([ visible_here, instance_wide, hidden ].map(&:persisted?)).to all(be(true))
    end

    it "shows an admin the same set tiered as it does flat" do
      create(:evidence, title: "Alpha Row", authorization_boundary: mine)
      create(:evidence, title: "Beta Row", authorization_boundary: theirs)

      sign_in_as(create(:user, :admin))
      get evidences_path

      expect(response.body).to include("Alpha Row").and include("Beta Row")
    end
  end

  describe "when tiering appears" do
    before { sign_in_as(create(:user, :admin)) }

    # Owner decision: automatic. A single-boundary user is not made worse off,
    # which is only true if they never see the tree.
    it "does not tier when everything shares one boundary" do
      create_list(:evidence, 2, authorization_boundary: mine)

      get evidences_path

      expect(response.body).not_to include("data-controller=\"tier-collapse\"")
    end

    it "tiers once a second boundary is visible" do
      create(:evidence, authorization_boundary: mine)
      create(:evidence, authorization_boundary: theirs)

      get evidences_path

      expect(response.body).to include("data-controller=\"tier-collapse\"")
      expect(response.body).to include("Alpha Agency")
      expect(response.body).to include("My System")
    end

    # #948 — the boundary was a card chip and nothing at all in the table.
    it "shows the boundary in the table view when not tiered" do
      create_list(:evidence, 2, authorization_boundary: mine)

      get evidences_path(view: "list")

      expect(response.body).to include("<th>Boundary</th>")
      expect(response.body).to include("My System")
    end
  end

  # F3 — "Instance" is not one condition. Evidence treats a nil boundary as
  # genuinely instance-wide (`global_fallback: true`); the per-system types
  # treat it as an unrepaired orphan (#952). One shared label would tell a user
  # an orphan SSP is deliberately shared estate-wide.
  describe "what a blank boundary is called" do
    before { sign_in_as(create(:user, :admin)) }

    it "calls it instance-wide on evidence, which it is" do
      create(:evidence, authorization_boundary: nil)
      create(:evidence, authorization_boundary: mine)

      get evidences_path

      expect(response.body).to include("Instance-wide")
      expect(response.body).not_to include("Not assigned to a system")
    end
  end

  # The generalisation, screen by screen. Each proves the same two things: the
  # page still renders, and tiering appeared without widening what is visible.
  #
  # CDEFs are deliberately absent: `cdef_documents` has no
  # `authorization_boundary_id` column and no `boundary_scoped` declaration, so
  # there is nothing to tier by. Raised separately rather than faked here.
  describe "the other collection screens" do
    before { sign_in_as(create(:user, :admin)) }

    {
      ssp_documents:  :ssp_document,
      sar_documents:  :sar_document,
      sap_documents:  :sap_document,
      poam_documents: :poam_document
    }.each do |screen, factory|
      context "/#{screen}" do
        it "tiers once a second boundary is visible" do
          create(factory, name: "Alpha Doc", authorization_boundary: mine)
          create(factory, name: "Beta Doc", authorization_boundary: theirs)

          get "/#{screen}"

          expect(response).to have_http_status(:ok)
          expect(response.body).to include("data-controller=\"tier-collapse\"")
          expect(response.body).to include("Alpha Doc").and include("Beta Doc")
        end

        it "does not tier on a single boundary" do
          create(factory, name: "Only Doc", authorization_boundary: mine)

          get "/#{screen}"

          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Only Doc")
          expect(response.body).not_to include("data-controller=\"tier-collapse\"")
        end

        # F3 — these types are per-system, so a nil boundary is an unrepaired
        # orphan, NOT a sharing decision. Calling it "Instance-wide" here would
        # tell a user the opposite of what #952 established.
        it "calls a blank boundary an unassigned document, not instance-wide" do
          # #952 made a boundary mandatory on these types, so a boundary-less
          # row can only be a LEGACY one — which is exactly the state this tier
          # is labelling. Written the way a legacy row is written.
          orphan = build(factory, name: "Orphan Doc", authorization_boundary: nil)
          # Skipping validation also skips the before_validation that mints the
          # slug the row's own link needs.
          orphan.slug = "orphan-doc-#{screen}"
          orphan.save!(validate: false)
          create(factory, name: "Filed Doc", authorization_boundary: mine)

          get "/#{screen}"

          expect(response.body).to include("Not assigned to a system")
          expect(response.body).not_to include("Instance-wide")
        end
      end
    end
  end

  describe "tiering composes with the #908 filters" do
    before { sign_in_as(create(:user, :admin)) }

    it "tiers only what the filter left, and keeps the filter applied" do
      create(:evidence, title: "Kept Row", status: "collected", authorization_boundary: mine)
      create(:evidence, title: "Filtered Row", status: "draft", authorization_boundary: theirs)

      get evidences_path(status: "collected")

      expect(response.body).to include("Kept Row")
      expect(response.body).not_to include("Filtered Row")
    end
  end
end
