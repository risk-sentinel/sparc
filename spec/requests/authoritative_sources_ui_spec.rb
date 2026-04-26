# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authoritative Sources UI", type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    sign_in_as(admin)
    allow_any_instance_of(ApplicationController).to receive(:require_authentication).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:check_session_timeout).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:check_password_reset).and_return(true)
  end

  let!(:authoritative) do
    BackMatterResource.create!(uuid: SecureRandom.uuid, title: "FedRAMP Baseline",
                               description: "Standard FedRAMP Moderate policy",
                               source: "authoritative", globally_available: true,
                               promotion_status: "approved")
  end

  let!(:archived) do
    BackMatterResource.create!(uuid: SecureRandom.uuid, title: "Old Standard",
                               source: "authoritative", globally_available: true,
                               promotion_status: "approved",
                               archived_at: 1.day.ago)
  end

  describe "GET /authoritative_sources" do
    it "lists active authoritative resources" do
      get authoritative_sources_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("FedRAMP Baseline")
      expect(response.body).not_to include("Old Standard") # archived hidden by default
    end

    it "filters by full-text query" do
      get authoritative_sources_path, params: { q: "FedRAMP" }
      expect(response.body).to include("FedRAMP Baseline")
    end

    it "filters by scope=authoritative" do
      managed = BackMatterResource.create!(uuid: SecureRandom.uuid, title: "Just managed",
                                           source: "managed",
                                           resourceable: create(:ssp_document))
      get authoritative_sources_path, params: { scope: "authoritative" }
      expect(response.body).to include("FedRAMP Baseline")
      expect(response.body).not_to include("Just managed")
    end
  end

  describe "GET /authoritative_sources/:id" do
    it "renders the resource detail page" do
      get authoritative_source_path(authoritative)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(authoritative.uuid)
      expect(response.body).to include("FedRAMP Baseline")
    end
  end
end
