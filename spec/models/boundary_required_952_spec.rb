# frozen_string_literal: true

require "rails_helper"

# #952 — SSP/SAP/SAR/POA&M must belong to an authorization boundary.
#
# A boundary-less one was treated as instance-wide and shown to EVERY signed-in
# user. Those four are per-system by definition: they carry the implementation
# detail and the open weaknesses for ONE boundary, so there is no such thing as
# an instance-wide SSP.
RSpec.describe "A per-system document requires a boundary (#952)" do
  # Keyed by factory so a type added to one list and not the other is obvious.
  def required_types
    { ssp_document: SspDocument, sap_document: SapDocument,
      sar_document: SarDocument, poam_document: PoamDocument }
  end

  describe "the four per-system types" do
    it "refuses to save without a boundary" do
      required_types.each do |factory_name, klass|
        record = build(factory_name, authorization_boundary: nil)

        expect(record).not_to be_valid, "#{klass}: expected a boundary to be required"
        expect(record.errors[:authorization_boundary]).to be_present
      end
    end

    it "saves with one" do
      boundary = create(:authorization_boundary)

      required_types.each do |factory_name, klass|
        record = build(factory_name, authorization_boundary: boundary)
        expect(record).to be_valid, "#{klass}: #{record.errors.full_messages.join(', ')}"
      end
    end

    it "refuses to have its boundary removed once set" do
      required_types.each do |factory_name, klass|
        record = create(factory_name)
        record.authorization_boundary = nil

        expect(record.save).to be(false), "#{klass}: expected detaching the boundary to be refused"
      end
    end
  end

  # The exemption is the interesting half: it is deliberate, and a future sweep
  # that "tidies up" by adding the same validation to Evidence would break
  # leveraging.
  describe "Evidence is deliberately EXEMPT" do
    it "saves with no boundary, because evidence is leveraged and inherited across them" do
      # An authorization can inherit a control implementation from the system it
      # leverages, and the artifact proving that control belongs to the provider,
      # not to the consumer's boundary. Requiring a boundary here would force
      # every inherited artifact to be duplicated per consuming boundary, which
      # is exactly what leveraging exists to avoid.
      evidence = build(:evidence, authorization_boundary: nil)

      expect(evidence).to be_valid
      expect { evidence.save! }.not_to raise_error
    end

    it "still accepts one when the artifact does belong to a single boundary" do
      evidence = build(:evidence, authorization_boundary: create(:authorization_boundary))
      expect(evidence).to be_valid
    end
  end

  # CDEFs are out of scope by design: a component definition states that a
  # control CAN be satisfied, not how it is implemented for a given system, so
  # instance-wide visibility is correct. It has no boundary column at all.
  describe "CdefDocument is out of scope" do
    it "has no authorization_boundary_id column to require" do
      expect(CdefDocument.column_names).not_to include("authorization_boundary_id")
    end
  end

  describe "legacy rows written before the rule" do
    it "still LOAD, so #929's attach flow can repair them" do
      orphan = create_legacy_orphan(:ssp_document, name: "Legacy Orphan")

      expect(SspDocument.find(orphan.id).authorization_boundary_id).to be_nil
      expect(SspDocument.find(orphan.id).name).to eq("Legacy Orphan")
    end

    it "become valid the moment a boundary is attached" do
      orphan = create_legacy_orphan(:ssp_document)

      expect(orphan.update(authorization_boundary: create(:authorization_boundary))).to be(true)
    end

    # `soft_delete!` uses `update_columns`, which skips validation — so an
    # orphan can still be deleted rather than being stuck un-saveable.
    it "can still be soft-deleted without first being repaired" do
      orphan = create_legacy_orphan(:sar_document)

      expect { orphan.soft_delete! }.not_to raise_error
      expect(orphan.reload.deleted_at).to be_present
    end
  end
end
