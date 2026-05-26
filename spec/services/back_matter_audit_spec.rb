# frozen_string_literal: true

require "rails_helper"

# #581 — BackMatterAudit emits BackMatterResourceChange rows for the
# CDEF write paths that produce new BackMatterResource records.
RSpec.describe BackMatterAudit do
  let(:cdef) { create(:cdef_document, name: "Audit Spec CDEF") }
  let(:resource) do
    BackMatterResource.create!(
      uuid:         SecureRandom.uuid,
      title:        "Test",
      source:       "managed",
      resourceable: cdef
    )
  end

  describe ".record_create" do
    it "creates a BackMatterResourceChange with change_type: create" do
      expect {
        described_class.record_create(resource)
      }.to change(BackMatterResourceChange, :count).by(1)

      change = resource.changes_log.last
      expect(change.change_type).to eq("create")
      expect(change.changed_at).to be_within(2.seconds).of(Time.current)
    end

    it "records the acting user when provided" do
      user = create(:user, email: "auditor@example.com")
      described_class.record_create(resource, user: user)
      expect(resource.changes_log.last.changed_by_user_id).to eq(user.id)
    end

    it "leaves changed_by_user_id nil for system / parser paths" do
      described_class.record_create(resource)
      expect(resource.changes_log.last.changed_by_user_id).to be_nil
    end

    it "groups multi-resource transactions under a shared batch_uuid" do
      batch = SecureRandom.uuid
      r1 = BackMatterResource.create!(uuid: SecureRandom.uuid, title: "A", source: "managed", resourceable: cdef)
      r2 = BackMatterResource.create!(uuid: SecureRandom.uuid, title: "B", source: "managed", resourceable: cdef)

      described_class.record_create(r1, batch_uuid: batch)
      described_class.record_create(r2, batch_uuid: batch)

      grouped = BackMatterResourceChange.for_batch(batch)
      expect(grouped.count).to eq(2)
      expect(grouped.pluck(:back_matter_resource_id)).to match_array([ r1.id, r2.id ])
    end

    it "returns nil and does not raise for an unpersisted resource" do
      unsaved = BackMatterResource.new(uuid: SecureRandom.uuid, title: "X", source: "managed")
      expect {
        result = described_class.record_create(unsaved)
        expect(result).to be_nil
      }.not_to change(BackMatterResourceChange, :count)
    end

    it "returns nil for a nil resource" do
      expect(described_class.record_create(nil)).to be_nil
    end
  end

  describe "integration: parser promotion path (#498/#581)" do
    let(:oscal_with_back_matter) do
      {
        "component-definition" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Parser audit test", "version" => "1.0", "oscal-version" => "1.1.2" },
          "components" => [],
          "back-matter" => {
            "resources" => [
              { "uuid" => SecureRandom.uuid, "title" => "Resource A" },
              { "uuid" => SecureRandom.uuid, "title" => "Resource B" }
            ]
          }
        }
      }
    end
    let(:tmp_fixture) do
      f = Tempfile.new([ "audit-parser-", ".json" ])
      f.write(JSON.generate(oscal_with_back_matter))
      f.close
      f.path
    end

    after { FileUtils.rm_f(tmp_fixture) }

    it "emits one create change per promoted resource, all sharing a batch_uuid" do
      CdefJsonParserService.new(cdef, tmp_fixture).parse(validate: false)
      cdef.reload
      changes = BackMatterResourceChange.where(back_matter_resource_id: cdef.back_matter_resources.pluck(:id))
      expect(changes.count).to eq(2)
      expect(changes.pluck(:change_type).uniq).to eq([ "create" ])
      expect(changes.pluck(:batch_uuid).uniq.length).to eq(1)
    end
  end
end
