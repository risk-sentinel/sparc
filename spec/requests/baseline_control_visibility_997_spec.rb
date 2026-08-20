# frozen_string_literal: true

require "rails_helper"

# #997 — a parameter update could succeed and the user had no way to see it.
# There was no web UI for baseline parameters at all, and nothing on the
# Profile or SSP screens said what was legitimately part of the profile: the
# Profile screen listed identifiers grouped by family with priority counts and
# stopped there.
#
# The posture is declared here rather than inherited from the environment —
# `authorize_permission!` short-circuits when no authentication is configured,
# and a permission test that runs with the guard disabled asserts nothing while
# still reporting green.
RSpec.describe "What the baseline requires, on screen (#997)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }

  let!(:catalog_control) do
    create(:catalog_control,
      control_family: family,
      control_id: "ac-20",
      title: "Use of External Systems",
      priority: "P2",
      guidance_data: {
        "statement" => "Establish {{ insert: param, ac-20_odp.01 }}, consistent with the trust relationships established with other organizations.",
        "supplemental_guidance" => "External systems are outside the authorization boundary.",
        "related_controls" => "ac-3, sc-7"
      },
      params_data: [
        { "id" => "ac-20_odp.01", "label" => "terms and conditions" },
        { "id" => "ac-20_odp.02",
          "select" => { "how-many" => "one-or-more", "choice" => [ "removes", "disables" ] } }
      ])
  end

  let(:profile) { create(:profile_document, control_catalog: catalog, status: "completed") }
  let!(:profile_control) do
    create(:profile_control, profile_document: profile, control_id: "ac-20",
                             title: "Use of External Systems", priority: "P2")
  end

  let(:reader) { create(:user) }
  let(:author) { create(:user).tap { |u| grant_permission(u, "profiles.write") } }

  describe "the Profile screen" do
    it "shows the control language, the guidance and the related controls" do
      sign_in_as(reader)
      get profile_document_path(profile)

      expect(response.body).to include("Establish")
      expect(response.body).to include("outside the authorization boundary")
      expect(response.body).to include("SC-7")
    end

    # The defect that makes showing it worse than not: raw OSCAL markup where
    # the organization-defined text belongs.
    it "never renders raw insert markup" do
      sign_in_as(reader)
      get profile_document_path(profile)

      expect(response.body).not_to match(/\{\{\s*insert/)
    end

    it "lists the parameters the baseline defines, with their ids" do
      sign_in_as(reader)
      get profile_document_path(profile)

      expect(response.body).to include("ac-20_odp.01")
      expect(response.body).to include("ac-20_odp.02")
    end

    context "the permission gate, proven in both directions" do
      it "offers the parameter form to a user holding profiles.write" do
        sign_in_as(author)
        get profile_document_path(profile)

        expect(response.body).to include("Save parameters")
        expect(response.body).to include("param_values[ac-20_odp.01]")
      end

      it "shows a user without profiles.write the values and no way to change them" do
        sign_in_as(reader)
        get profile_document_path(profile)

        expect(response.body).to include("ac-20_odp.01")
        expect(response.body).not_to include("Save parameters")
        expect(response.body).not_to include("param_values[ac-20_odp.01]")
      end

      it "refuses the write itself, not merely the button" do
        sign_in_as(reader)
        patch parameters_profile_document_profile_control_path(profile, profile_control),
              params: { param_values: { "ac-20_odp.01" => "smuggled" } }

        expect(response).not_to have_http_status(:ok)
        expect(ProfileControlField.find_by(field_name: "parameter:ac-20_odp.01")).to be_nil
      end
    end
  end

  # The defect the issue opens with: an update that succeeds and cannot be seen.
  describe "a parameter change made in the UI" do
    before { sign_in_as(author) }

    it "is visible on the screen immediately afterwards" do
      patch parameters_profile_document_profile_control_path(profile, profile_control),
            params: { param_values: { "ac-20_odp.01" => "the Acme access terms" } }
      follow_redirect!

      expect(response.body).to include("the Acme access terms")
    end

    it "substitutes the new value into the control statement, not just the field" do
      patch parameters_profile_document_profile_control_path(profile, profile_control),
            params: { param_values: { "ac-20_odp.01" => "the Acme access terms" } }
      follow_redirect!

      expect(response.body).to include("Establish the Acme access terms")
    end

    it "applies a selection posted as a checkbox group" do
      patch parameters_profile_document_profile_control_path(profile, profile_control),
            params: { param_values: { "ac-20_odp.02" => [ "", "removes" ] } }

      field = ProfileControlField.find_by(field_name: "parameter:ac-20_odp.02")
      expect(field.field_value).to eq("removes")
    end

    # Writing through BaselineParameterService is what gives the web form the
    # same validation as the API (#994); a bare field write would accept this.
    it "does not write a parameter the catalog does not define" do
      patch parameters_profile_document_profile_control_path(profile, profile_control),
            params: { param_values: { "not_a_real_param" => "x" } }

      expect(ProfileControlField.find_by(field_name: "parameter:not_a_real_param")).to be_nil
    end
  end

  describe "the SSP screen" do
    # An SSP is boundary-scoped, and the read-only claim is strongest when the
    # user it is proven against is the one who could do anything: if an ADMIN is
    # offered no way to edit a parameter here, nobody is.
    let(:admin) { create(:user, :admin) }
    let(:boundary) { create(:authorization_boundary) }
    let(:ssp) do
      create(:ssp_document, profile_document: profile, authorization_boundary: boundary,
                            status: "completed")
    end
    let!(:ssp_control) do
      create(:ssp_control, ssp_document: ssp, control_id: "ac-20", title: "Use of External Systems")
    end

    before do
      create(:profile_control_field, profile_control: profile_control,
                                     field_name: "parameter:ac-20_odp.01",
                                     field_value: "the Acme access terms")
    end

    it "shows the same content with the baseline's values applied" do
      sign_in_as(admin)
      get ssp_document_path(ssp)

      expect(response.body).to include("Establish the Acme access terms")
    end

    # Owner direction: the SSP consumes the baseline, it does not define it.
    it "offers no way to edit a parameter, even to an admin" do
      sign_in_as(admin)
      get ssp_document_path(ssp)

      expect(response.body).not_to include("Save parameters")
      expect(response.body).not_to include("param_values[ac-20_odp.01]")
    end
  end
end
