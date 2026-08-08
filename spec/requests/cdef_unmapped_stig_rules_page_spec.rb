# frozen_string_literal: true

require "rails_helper"

# #911 — the CDEF page must render when a STIG rule maps to no control.
#
# This exists because the model-and-export specs did not catch the obvious
# consequence of making `control_id` NULL: the show view derived a family with
# `control.control_id.to_s.split("-").first.upcase`, and `"".split("-").first`
# is nil, so the page 500'd for exactly the documents the feature was written
# for. Asserting on the model proved the data was right and proved nothing about
# whether anyone could look at it.
RSpec.describe "CDEF page with unmapped STIG rules", type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(admin)
  end

  let(:cdef) { create(:cdef_document, file_type: "xccdf", status: "completed") }

  before do
    cdef.cdef_controls.create!(control_id: "ac-2", control_family: "AC",
                               title: "Mapped rule", row_order: 0)
    # No control_id and no control_family — the state the parser now produces
    # for a STIG rule the CCI mapping does not cover.
    cdef.cdef_controls.create!(stig_id: "SV-999999r000001_rule",
                               rule_id: "SV-999999r000001_rule",
                               group_id: "V-999999",
                               title: "Unmapped rule", row_order: 1)
  end

  it "renders rather than raising on the control with no family" do
    get cdef_document_path(cdef)

    expect(response).to have_http_status(:ok)
  end

  it "still shows the mapped control" do
    get cdef_document_path(cdef)

    expect(response.body).to include("Mapped rule")
  end

  # The rule is not silently dropped from the page — it is listed under the
  # identifier it does have.
  it "lists the unmapped rule by its STIG identifier" do
    get cdef_document_path(cdef)

    expect(response.body).to include("Unmapped rule")
    expect(response.body).to include("SV-999999r000001_rule")
  end
end
