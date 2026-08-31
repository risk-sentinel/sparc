# frozen_string_literal: true

require "rails_helper"

# #968 item 3 — the operator-visible half of the partial-success contract.
#
# The API field is asserted in spec/requests/api/v1/cdef_index_degradation_968_spec.rb.
# This covers the screens, because a field nobody renders is not visibility: the
# whole finding was that a degraded import looked identical to a clean one
# everywhere a person actually looks.
#
# Asserted in BOTH directions on BOTH screens. A badge rendered unconditionally
# would satisfy the degraded case alone and would be worse than none — every
# document would look broken.
RSpec.describe "CdefDocuments component-index degradation badge (#968)", type: :request do
  let(:admin) { create(:user, :admin) }

  before { sign_in_as(admin) }

  def degrade!(doc)
    doc.update_column(
      :import_metadata,
      (doc.import_metadata || {}).merge("component_index_failed_at" => "2026-08-31T00:00:00Z")
    )
    doc
  end

  describe "the show page" do
    it "flags a document whose component index failed" do
      doc = degrade!(create(:cdef_document, name: "Degraded CDEF", status: "completed"))

      get cdef_document_path(doc)

      expect(response.body).to include("cdef-index-degraded")
      expect(response.body).to include("Component index degraded")
    end

    it "says nothing on a clean document" do
      doc = create(:cdef_document, name: "Clean CDEF", status: "completed")

      get cdef_document_path(doc)

      expect(response.body).not_to include("cdef-index-degraded")
    end
  end

  describe "the index" do
    it "flags the degraded row and leaves the clean one alone" do
      degraded = degrade!(create(:cdef_document, name: "Degraded CDEF", status: "completed"))
      create(:cdef_document, name: "Clean CDEF", status: "completed")

      get cdef_documents_path(view: "list")

      expect(response.body).to include("cdef-index-degraded")
      # exactly one row carries the marker — the degraded one
      expect(response.body.scan("cdef-index-degraded").length).to eq(1)
      expect(degraded.reload).to be_component_index_degraded
    end
  end
end
