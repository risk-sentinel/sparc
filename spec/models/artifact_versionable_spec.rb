# frozen_string_literal: true

require "rails_helper"

# #680 — evidence artifact version history. Verifies a new ArtifactVersion is
# minted on every MATERIAL change (file re-upload, attestation re-review), that
# the back-matter-bound UUID changes while the logical identity stays, and —
# the load-bearing assertion — that every prior version's content is RETAINED
# (not purged) across a re-upload.
RSpec.describe "Evidence artifact versioning (#680)", type: :model do
  def attach(evidence, bytes, filename: "doc.pdf")
    evidence.file.attach(io: StringIO.new(bytes), filename: filename, content_type: "application/pdf")
    evidence.compute_file_hash!
    evidence
  end

  let(:evidence) { create(:evidence, title: "SOC 2") }

  describe "minting" do
    it "mints an initial version when a file is first attached" do
      attach(evidence, "AAAA")
      expect(evidence.artifact_versions.count).to eq(1)
      v = evidence.current_artifact_version
      expect(v).to be_current
      expect(v.uuid).to be_present
      expect(v.file_hash).to eq(evidence.file_hash)
      expect(v.content).to be_attached
    end

    it "does not mint a new version when nothing material changed" do
      attach(evidence, "AAAA")
      expect { evidence.update!(title: "SOC 2 (renamed)") }
        .not_to change { evidence.artifact_versions.count }
    end

    it "mints a new version on file re-upload and supersedes the prior one" do
      attach(evidence, "AAAA")
      v1 = evidence.current_artifact_version

      attach(evidence, "BBBB")
      expect(evidence.artifact_versions.count).to eq(2)
      v2 = evidence.current_artifact_version

      expect(v2.uuid).not_to eq(v1.uuid)          # version-aware identity changed
      expect(v1.reload).to be_superseded            # superseded_at set
      expect(v2).to be_current
    end

    it "mints a new version when an attestation is reviewed (same file, new date)" do
      attach(evidence, "AAAA")
      v1 = evidence.current_artifact_version

      create(:attestation, evidence: evidence, attested_at: Time.current, status: "passed")
      expect(evidence.artifact_versions.count).to eq(2)
      v2 = evidence.reload.current_artifact_version

      expect(v2.uuid).not_to eq(v1.uuid)
      expect(v2.file_hash).to eq(v1.file_hash)      # same file...
      expect(v2.attester_snapshot.size).to eq(1)    # ...but the review is captured
      expect(v2.reviewed_at).to be_present
    end
  end

  describe "per-version content retention (the load-bearing check)" do
    it "retains every prior version's content across a re-upload" do
      attach(evidence, "AAAA")
      v1 = evidence.current_artifact_version

      attach(evidence, "BBBB")
      v2 = evidence.current_artifact_version

      # v1's content must STILL be downloadable as the original bytes — proving
      # the re-upload did not purge the blob v1 references.
      expect(v1.reload.content).to be_attached
      expect(v1.content.download).to eq("AAAA")
      expect(v2.content.download).to eq("BBBB")
    end
  end

  describe "logical identity is stable" do
    it "keeps the same resolver URL (location) across versions" do
      attach(evidence, "AAAA")
      url_before = evidence.oscal_resolver_url
      attach(evidence, "BBBB")
      expect(evidence.oscal_resolver_url).to eq(url_before)
    end
  end

  describe "OSCAL back-matter emission" do
    it "emits the current version UUID + drift props for evidence-backed resources" do
      attach(evidence, "AAAA")
      version = evidence.current_artifact_version

      bmr = BackMatterResource.new(
        uuid: SecureRandom.uuid, title: evidence.title, evidence: evidence, source: "managed"
      )
      oscal = bmr.to_oscal_resource

      # uuid is the version (not the stable evidence/logical id)…
      expect(oscal["uuid"]).to eq(version.uuid)
      expect(oscal["uuid"]).not_to eq(evidence.uuid)
      # …with a stable logical-id (drift matching) + reviewed-date (cadence delta)
      expect(oscal["props"]).to include({ "name" => "logical-id", "value" => evidence.uuid })
      expect(oscal["props"].find { |p| p["name"] == "reviewed-date" }).to be_present
      # …while the link (location) stays the stable resolver URL
      expect(oscal["rlinks"].first["href"]).to eq(evidence.oscal_resolver_url)
    end
  end
end
