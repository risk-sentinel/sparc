require "rails_helper"

RSpec.describe "OscalMetadata UUID handling", type: :model do
  # Use CdefDocument as our test subject since it includes OscalMetadata
  # and is lightweight to create.
  let(:document) { create(:cdef_document) }

  describe "#assign_oscal_uuid!" do
    context "with a valid unique UUID" do
      it "assigns the source UUID to the document" do
        valid_uuid = SecureRandom.uuid
        document.assign_oscal_uuid!(valid_uuid)
        expect(document.reload.uuid).to eq(valid_uuid)
      end

      it "does not set uuid_replaced in import_metadata" do
        document.assign_oscal_uuid!(SecureRandom.uuid)
        expect(document.reload.import_metadata&.dig("uuid_replaced")).to be_nil
      end
    end

    context "with a blank UUID" do
      it "does nothing" do
        original_uuid = document.uuid
        document.assign_oscal_uuid!(nil)
        expect(document.reload.uuid).to eq(original_uuid)
      end

      it "does nothing for empty string" do
        original_uuid = document.uuid
        document.assign_oscal_uuid!("")
        expect(document.reload.uuid).to eq(original_uuid)
      end
    end

    context "with a UUID collision" do
      let!(:existing_doc) { create(:cdef_document) }

      before do
        # Force a known UUID on the existing doc
        existing_doc.update_column(:uuid, "deadbeef-1234-4000-a000-000000000001")
      end

      it "does NOT assign the colliding UUID" do
        original_uuid = document.uuid
        document.assign_oscal_uuid!("deadbeef-1234-4000-a000-000000000001")
        expect(document.reload.uuid).to eq(original_uuid)
      end

      it "preserves the original UUID in import_metadata" do
        document.assign_oscal_uuid!("deadbeef-1234-4000-a000-000000000001")
        meta = document.reload.import_metadata
        expect(meta["original_uuid"]).to eq("deadbeef-1234-4000-a000-000000000001")
        expect(meta["uuid_replaced"]).to be true
        expect(meta["uuid_replace_reason"]).to eq("collision")
        expect(meta["uuid_collision_with"]).to eq(existing_doc.id)
      end
    end

    context "with a placeholder UUID (valid v4 format but sequential pattern)" do
      it "does NOT assign the placeholder UUID" do
        original_uuid = document.uuid
        document.assign_oscal_uuid!("a1b2c3d4-1111-4000-a000-000000000008")
        expect(document.reload.uuid).to eq(original_uuid)
      end

      it "preserves the original placeholder in import_metadata" do
        document.assign_oscal_uuid!("a1b2c3d4-1111-4000-a000-000000000008")
        meta = document.reload.import_metadata
        expect(meta["original_uuid"]).to eq("a1b2c3d4-1111-4000-a000-000000000008")
        expect(meta["uuid_replaced"]).to be true
        expect(meta["uuid_replace_reason"]).to eq("placeholder_pattern")
      end

      it "detects consecutive zeros pattern" do
        original_uuid = document.uuid
        document.assign_oscal_uuid!("deadbeef-dead-4eef-beef-000000000001")
        expect(document.reload.uuid).to eq(original_uuid)
        expect(document.reload.import_metadata["uuid_replace_reason"]).to eq("placeholder_pattern")
      end
    end

    context "with invalid RFC 4122 v4 format" do
      it "rejects UUIDs with wrong version nibble" do
        original_uuid = document.uuid
        document.assign_oscal_uuid!("f7e6d5c4-b3a2-1190-8877-665544332211")
        expect(document.reload.uuid).to eq(original_uuid)
        expect(document.reload.import_metadata["uuid_replace_reason"]).to eq("non_rfc4122_format")
      end

      it "rejects UUIDs with wrong variant nibble" do
        original_uuid = document.uuid
        document.assign_oscal_uuid!("f7e6d5c4-b3a2-4190-0877-665544332211")
        expect(document.reload.uuid).to eq(original_uuid)
        expect(document.reload.import_metadata["uuid_replaced"]).to be true
      end
    end

    context "re-importing the same file twice" do
      it "first import assigns UUID, second gets fresh UUID" do
        uuid = SecureRandom.uuid

        # First import
        doc1 = create(:cdef_document)
        doc1.assign_oscal_uuid!(uuid)
        expect(doc1.reload.uuid).to eq(uuid)

        # Second import with same UUID
        doc2 = create(:cdef_document)
        original_doc2_uuid = doc2.uuid
        doc2.assign_oscal_uuid!(uuid)
        expect(doc2.reload.uuid).to eq(original_doc2_uuid) # kept auto-generated
        expect(doc2.reload.import_metadata["uuid_replaced"]).to be true
        expect(doc2.reload.import_metadata["uuid_collision_with"]).to eq(doc1.id)
      end
    end
  end

  describe "#store_replaced_uuid" do
    it "stores collision metadata" do
      document.store_replaced_uuid("old-uuid-here", collision_with: 42)
      meta = document.reload.import_metadata
      expect(meta["original_uuid"]).to eq("old-uuid-here")
      expect(meta["uuid_replaced"]).to be true
      expect(meta["uuid_collision_with"]).to eq(42)
      expect(meta["uuid_replace_reason"]).to eq("collision")
    end

    it "stores placeholder metadata" do
      document.store_replaced_uuid("placeholder-uuid", reason: "non_rfc4122_placeholder")
      meta = document.reload.import_metadata
      expect(meta["original_uuid"]).to eq("placeholder-uuid")
      expect(meta["uuid_replace_reason"]).to eq("non_rfc4122_placeholder")
    end

    it "preserves existing import_metadata fields" do
      document.update_column(:import_metadata, { "existing_key" => "existing_value" })
      document.store_replaced_uuid("some-uuid")
      meta = document.reload.import_metadata
      expect(meta["existing_key"]).to eq("existing_value")
      expect(meta["original_uuid"]).to eq("some-uuid")
    end
  end
end
