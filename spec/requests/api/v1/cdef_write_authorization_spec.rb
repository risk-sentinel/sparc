# frozen_string_literal: true

require "rails_helper"

# #1032 — every CDEF write over the API requires `cdef.write`.
#
# They ran no permission check at all: the permission existed, the web
# controller gated the same actions on it, and the API did not — so `cdef.write`
# was not a permission a user could be denied through the API, only one they
# could route around by using it. CDEF was the only API document controller with
# ungated writes.
#
# Both directions per action. An allow-leg-only test passes identically against
# an endpoint with no guard, which is how #919 and #974 were found.
RSpec.describe "Api::V1 CDEF write authorization", type: :request do
  let(:user) { create(:user) }
  let(:headers) do
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'T').plaintext_token}" }
  end
  let(:baseline) { create(:profile_document, control_catalog: create(:control_catalog)) }
  let!(:cdef) { create(:cdef_document, profile_document: baseline) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  # Each entry is [description, ->(spec) { the request }].
  # Declared as a method rather than a constant: a constant assigned in a
  # describe block is defined at TOP LEVEL and leaks into the whole suite.
  def self.each_write(&block)
    {
      "create"              => ->(s) { s.post "/api/v1/cdef_documents",
                                              params: { cdef_document: { name: "X", cdef_type: "custom" } },
                                              headers: s.headers, as: :json },
      "update"              => ->(s) { s.put "/api/v1/cdef_documents/#{s.cdef.slug}",
                                             params: { cdef_document: { name: "Renamed" } },
                                             headers: s.headers, as: :json },
      "destroy"             => ->(s) { s.delete "/api/v1/cdef_documents/#{s.cdef.slug}", headers: s.headers },
      "source_from_profile" => ->(s) { s.post "/api/v1/cdef_documents/#{s.cdef.slug}/source_from_profile",
                                              params: { source_profile_id: s.baseline.slug },
                                              headers: s.headers, as: :json },
      "submit_for_review"   => ->(s) { s.post "/api/v1/cdef_documents/#{s.cdef.slug}/submit_for_review",
                                              headers: s.headers, as: :json },
      "update_scope"        => ->(s) { s.patch "/api/v1/cdef_documents/#{s.cdef.slug}/scope",
                                              params: { scope: "global" }, headers: s.headers, as: :json }
    }.each(&block)
  end

  each_write do |action, request|
    describe "#{action} without cdef.write" do
      it "is refused" do
        request.call(self)

        expect(response).to have_http_status(:forbidden),
          "#{action} answered #{response.status} for a user holding no permissions"
      end
    end

    describe "#{action} with cdef.write" do
      it "is allowed" do
        grant_permission(user, "cdef.write")

        request.call(self)

        expect(response).not_to have_http_status(:forbidden),
          "#{action} refused a caller who holds cdef.write: #{response.body[0, 200]}"
      end
    end
  end

  # The gate must not reach past the write actions. A read that started
  # returning 403 would be a different bug introduced by the fix.
  describe "reads are unaffected" do
    it "allows index without cdef.write" do
      get "/api/v1/cdef_documents", headers: headers

      expect(response).to have_http_status(:ok)
    end

    it "allows show without cdef.write" do
      get "/api/v1/cdef_documents/#{cdef.slug}", headers: headers

      expect(response).to have_http_status(:ok)
    end

    it "allows export without cdef.write" do
      get "/api/v1/cdef_documents/#{cdef.slug}/export", headers: headers

      expect(response).to have_http_status(:ok)
    end
  end
end
