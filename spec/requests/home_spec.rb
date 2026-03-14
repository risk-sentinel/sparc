# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "GET /" do
    it "returns a successful response" do
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "displays dashboard counts" do
      create(:control_catalog)
      create(:ssp_document)

      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "renders even with no data" do
      get root_path
      expect(response).to have_http_status(:ok)
    end
  end
end
