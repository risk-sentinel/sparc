# frozen_string_literal: true

require "rails_helper"

# Issue #535 — every admin page that lives under /admin/* is reachable from
# the User dropdown's "Administration" section. Service Accounts had been
# orphaned (only linked from the Enterprise dropdown), making the page
# undiscoverable for new admins.
RSpec.describe "Admin navigation", type: :request do
  # The User dropdown (and its admin links) only renders when at least one
  # auth provider is enabled. CI test env has none enabled by default, so
  # stub the predicate to mirror the deployed reality.
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  context "when signed in as an admin" do
    let(:admin) { create(:user, :admin) }

    before { sign_in_as(admin) }

    it "links every /admin/* page from the User dropdown's Administration section" do
      get root_path
      expect(response).to have_http_status(:ok)

      expect(response.body).to include(%(href="#{admin_users_path}"))
      expect(response.body).to include(%(href="#{admin_roles_path}"))
      expect(response.body).to include(%(href="#{admin_service_accounts_path}"))
      expect(response.body).to include(%(href="#{admin_authorization_boundaries_path}"))
      expect(response.body).to include(%(href="#{admin_organizations_path}"))
      expect(response.body).to include(%(href="#{admin_audit_logs_path}"))
    end
  end

  context "when signed in as a non-admin" do
    let(:user) { create(:user) }

    before { sign_in_as(user) }

    it "does not link admin pages from the User dropdown" do
      get root_path
      expect(response).to have_http_status(:ok)

      expect(response.body).not_to include(%(href="#{admin_users_path}"))
      expect(response.body).not_to include(%(href="#{admin_service_accounts_path}"))
    end
  end
end
