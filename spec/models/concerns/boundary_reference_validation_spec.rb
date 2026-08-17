# frozen_string_literal: true

require "rails_helper"

# `belongs_to :authorization_boundary, optional: true` makes the association
# optional; it does NOT make a supplied id valid. A stale id resolved to a nil
# association while still being written, so PostgreSQL raised
# ActiveRecord::InvalidForeignKey and the API answered 500 for ordinary bad
# input. Each example below pairs the VALID case with the INVALID one so the
# validation is shown to reject only what it should.
RSpec.describe BoundaryReferenceValidation do
  MODELS = {
    ssp_document: SspDocument,
    sar_document: SarDocument,
    sap_document: SapDocument,
    poam_document: PoamDocument,
    evidence: Evidence
  }.freeze

  MODELS.each do |factory_name, klass|
    describe klass do
      it "accepts a boundary that exists" do
        boundary = create(:authorization_boundary)
        record = build(factory_name, authorization_boundary: boundary)
        expect(record).to be_valid
      end

      # #952 — the ASSOCIATION is still optional; what changed is that
      # SSP/SAP/SAR/POA&M carry a separate presence validation because those
      # types are per-system. Evidence has none: it is leveraged and inherited
      # across boundaries, so a boundary-less evidence record is legitimate.
      # This concern's own rule — "a supplied id must resolve" — is unchanged
      # for all five, which is what the next example pins.
      it "leaves the boundary-less case to each model's own rule" do
        record = build(factory_name, authorization_boundary: nil)

        if klass == Evidence
          expect(record).to be_valid
        else
          expect(record).not_to be_valid
          expect(record.errors[:authorization_boundary]).to be_present
        end
      end

      it "rejects a boundary id with no matching row instead of hitting the FK" do
        record = build(factory_name, authorization_boundary: nil)
        record.authorization_boundary_id = 999_999_999

        expect(record).not_to be_valid
        expect(record.errors[:authorization_boundary_id])
          .to include("references a boundary that does not exist")

        # The point of validating: save fails as a RecordInvalid the API maps to
        # 422, NOT as the database-level ActiveRecord::InvalidForeignKey that
        # escaped unhandled and produced a 500.
        expect { record.save! }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end
end
