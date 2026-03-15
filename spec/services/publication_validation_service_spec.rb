# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicationValidationService do
  let(:document) { create(:ssp_document) }
  let(:user) { create(:user, display_name: "Jane Doe", email: "jane@example.com") }
  let(:org) { create(:organization, :with_contact, name: "ACME Corp", contact_email: "contact@acme.com") }

  describe "#validate" do
    context "with complete metadata" do
      before do
        document.update!(metadata_extra: {
          "roles" => [ { "id" => "prepared-by", "title" => "Prepared By" } ],
          "parties" => [ { "uuid" => SecureRandom.uuid, "type" => "organization", "name" => "ACME Corp" } ],
          "responsible-parties" => [ { "role-id" => "prepared-by", "party-uuids" => [ SecureRandom.uuid ] } ]
        })
      end

      it "returns valid" do
        result = described_class.new(document).validate
        expect(result.valid?).to be true
        expect(result.errors).to be_empty
        expect(result.missing_fields).to be_empty
      end
    end

    context "with no metadata" do
      it "returns invalid with all three errors" do
        result = described_class.new(document).validate
        expect(result.valid?).to be false
        expect(result.errors).to include(a_string_matching(/creator/i))
        expect(result.errors).to include(a_string_matching(/party/i))
        expect(result.errors).to include(a_string_matching(/responsible-party/i))
        expect(result.missing_fields).to contain_exactly(:creator_role, :contact_party, :responsible_parties)
      end
    end

    context "missing creator role only" do
      before do
        document.update!(metadata_extra: {
          "roles" => [ { "id" => "authorizer", "title" => "Authorizer" } ],
          "parties" => [ { "uuid" => SecureRandom.uuid, "name" => "ACME" } ],
          "responsible-parties" => [ { "role-id" => "authorizer", "party-uuids" => [ SecureRandom.uuid ] } ]
        })
      end

      it "reports missing creator_role" do
        result = described_class.new(document).validate
        expect(result.valid?).to be false
        expect(result.missing_fields).to include(:creator_role)
        expect(result.missing_fields).not_to include(:contact_party)
      end
    end

    context "missing parties only" do
      before do
        document.update!(metadata_extra: {
          "roles" => [ { "id" => "creator", "title" => "Creator" } ],
          "parties" => [],
          "responsible-parties" => [ { "role-id" => "creator", "party-uuids" => [ SecureRandom.uuid ] } ]
        })
      end

      it "reports missing contact_party" do
        result = described_class.new(document).validate
        expect(result.valid?).to be false
        expect(result.missing_fields).to include(:contact_party)
        expect(result.missing_fields).not_to include(:creator_role)
      end
    end

    context "missing responsible-parties only" do
      before do
        document.update!(metadata_extra: {
          "roles" => [ { "id" => "prepared-by", "title" => "Prepared By" } ],
          "parties" => [ { "uuid" => SecureRandom.uuid, "name" => "ACME" } ],
          "responsible-parties" => []
        })
      end

      it "reports missing responsible_parties" do
        result = described_class.new(document).validate
        expect(result.valid?).to be false
        expect(result.missing_fields).to include(:responsible_parties)
        expect(result.missing_fields).not_to include(:creator_role)
        expect(result.missing_fields).not_to include(:contact_party)
      end
    end
  end

  describe "#auto_populate_defaults!" do
    context "with a user who has an organization" do
      before do
        create(:organization_membership, user: user, organization: org)
      end

      it "adds prepared-by role, organization party, and responsible-party" do
        service = described_class.new(document, current_user: user)
        service.auto_populate_defaults!

        extra = document.metadata_extra
        expect(extra["roles"]).to include(a_hash_including("id" => "prepared-by"))
        expect(extra["parties"].first["type"]).to eq("organization")
        expect(extra["parties"].first["name"]).to eq("ACME Corp")
        expect(extra["responsible-parties"]).to include(
          a_hash_including("role-id" => "prepared-by")
        )
      end
    end

    context "with a user without organization" do
      it "adds person party from user profile" do
        service = described_class.new(document, current_user: user)
        service.auto_populate_defaults!

        extra = document.metadata_extra
        expect(extra["parties"].first["type"]).to eq("person")
        expect(extra["parties"].first["name"]).to eq("Jane Doe")
      end
    end

    context "without a current_user" do
      it "does nothing" do
        service = described_class.new(document)
        service.auto_populate_defaults!

        expect(document.metadata_extra).to be_blank
      end
    end

    context "preserves existing metadata" do
      before do
        document.update!(metadata_extra: {
          "roles" => [ { "id" => "prepared-by", "title" => "Existing Role" } ],
          "parties" => [ { "uuid" => "existing-uuid", "name" => "Existing Party" } ],
          "responsible-parties" => [ { "role-id" => "prepared-by", "party-uuids" => [ "existing-uuid" ] } ]
        })
      end

      it "does not overwrite existing entries" do
        service = described_class.new(document, current_user: user)
        service.auto_populate_defaults!

        extra = document.metadata_extra
        expect(extra["roles"].first["title"]).to eq("Existing Role")
        expect(extra["parties"].first["name"]).to eq("Existing Party")
      end
    end
  end

  describe "#publication_readiness" do
    it "returns correct structure" do
      service = described_class.new(document, current_user: user)
      readiness = service.publication_readiness

      expect(readiness).to include(:ready, :errors, :missing_fields, :checks, :defaults, :current_metadata)
      expect(readiness[:checks]).to include(:creator_role, :contact_party, :responsible_parties, :title, :version, :oscal_version)
      expect(readiness[:defaults]).to include(:creator_name, :creator_email, :party_type)
    end

    context "with complete metadata" do
      before do
        document.update!(metadata_extra: {
          "roles" => [ { "id" => "prepared-by", "title" => "Prepared By" } ],
          "parties" => [ { "uuid" => SecureRandom.uuid, "name" => "ACME" } ],
          "responsible-parties" => [ { "role-id" => "prepared-by", "party-uuids" => [ SecureRandom.uuid ] } ]
        })
      end

      it "returns ready: true" do
        readiness = described_class.new(document).publication_readiness
        expect(readiness[:ready]).to be true
      end
    end

    context "without metadata" do
      it "returns ready: false with errors" do
        readiness = described_class.new(document).publication_readiness
        expect(readiness[:ready]).to be false
        expect(readiness[:errors]).not_to be_empty
      end
    end
  end
end
