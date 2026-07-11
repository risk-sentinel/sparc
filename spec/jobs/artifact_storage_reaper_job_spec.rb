# frozen_string_literal: true

require "rails_helper"

# #690 (Phase 3 of #680) — artifact storage-hygiene reaper. Report-only by
# default; destructive purge gated on SPARC_ARTIFACT_REAPER_PURGE.
RSpec.describe ArtifactStorageReaperJob, type: :job do
  def unattached_blob(created_at:)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("orphan-bytes"), filename: "orphan.pdf", content_type: "application/pdf"
    ).tap { |b| b.update_column(:created_at, created_at) }
  end

  def back_matter(href)
    BackMatterResource.create!(title: "res", uuid: SecureRandom.uuid, source: "managed", href: href)
  end

  describe "orphan-blob sweep" do
    it "reports unattached blobs older than the grace window (no purge by default)" do
      unattached_blob(created_at: 2.days.ago)

      ob = described_class.new.perform[:orphan_blobs]
      expect(ob[:unreferenced]).to be >= 1
      expect(ob[:cleaning_enabled]).to be(false)
      expect(ob[:purged]).to eq(0)
    end

    it "ignores blobs within the grace window (in-flight uploads)" do
      before = described_class.new.perform[:orphan_blobs][:unreferenced]
      unattached_blob(created_at: 1.hour.ago) # younger than the 24h default

      after = described_class.new.perform[:orphan_blobs][:unreferenced]
      expect(after).to eq(before)
    end

    it "does not count a blob still attached to evidence" do
      evidence = create(:evidence)
      evidence.file.attach(io: StringIO.new("live"), filename: "e.pdf", content_type: "application/pdf")
      ActiveStorage::Blob.where(id: evidence.file.blob.id).update_all(created_at: 2.days.ago)

      ob = described_class.new.perform[:orphan_blobs]
      expect(ob[:unreferenced]).to eq(0)
    end

    it "purges when SPARC_ARTIFACT_REAPER_PURGE is enabled" do
      allow(SparcConfig).to receive(:artifact_reaper_purge?).and_return(true)
      unattached_blob(created_at: 2.days.ago)

      ob = described_class.new.perform[:orphan_blobs]
      expect(ob[:cleaning_enabled]).to be(true)
      expect(ob[:purged]).to be >= 1
    end
  end

  describe "dangling back-matter href scan" do
    it "flags an href whose artifact uuid no longer resolves" do
      dangling = back_matter("https://sparc.test/artifacts/#{SecureRandom.uuid}")

      ids = described_class.new.perform[:dangling_hrefs].map { |d| d[:back_matter_resource_id] }
      expect(ids).to include(dangling.id)
    end

    it "does not flag an href that resolves to live evidence" do
      evidence  = create(:evidence)
      resolving = back_matter("https://sparc.test/artifacts/#{evidence.uuid}")

      ids = described_class.new.perform[:dangling_hrefs].map { |d| d[:back_matter_resource_id] }
      expect(ids).not_to include(resolving.id)
    end

    it "ignores hrefs that are not artifact resolver URLs" do
      external = back_matter("https://example.com/some/document.pdf")

      ids = described_class.new.perform[:dangling_hrefs].map { |d| d[:back_matter_resource_id] }
      expect(ids).not_to include(external.id)
    end
  end
end
