# frozen_string_literal: true

require "rails_helper"

# #830 — end-to-end proof that a real `attach` produces a structured key.
#
# StorageKeyService can be unit-tested in isolation, but that proves only that
# the string is built correctly. What actually has to hold is that ActiveStorage
# USES it: the key is assigned in
# `ActiveStorage::Attached::Changes::CreateOne#find_or_build_blob`, because at
# Blob-create time the blob does not yet know what it is attached to.
RSpec.describe "structured storage keys (#830)" do
  let(:organization) { create(:organization, name: "Acme Corp") }
  let(:boundary)     { create(:authorization_boundary, name: "Cloud ATO", organization: organization) }

  def upload(content: "hello", filename: "artifact.json")
    { io: StringIO.new(content), filename: filename, content_type: "application/json" }
  end

  it "assigns a structured key when a file is attached to evidence" do
    evidence = create(:evidence, authorization_boundary: boundary)
    evidence.file.attach(**upload)

    expect(evidence.file.blob.key).to start_with("org/acme-corp/boundary/cloud-ato/evidence/")
  end

  it "assigns a structured key to a document upload" do
    ssp = create(:ssp_document, authorization_boundary: boundary)
    ssp.file.attach(**upload)

    expect(ssp.file.blob.key).to include("/documents/ssp/")
  end

  it "assigns a structured key to an avatar, with no boundary involved" do
    user = create(:user)
    user.avatar.attach(**upload(filename: "face.png"))

    expect(user.avatar.blob.key).to start_with("instance/users/#{user.id}/avatar/")
  end

  it "no longer writes any attachment to the bucket root" do
    evidence = create(:evidence, authorization_boundary: boundary)
    evidence.file.attach(**upload)

    # The old behaviour was a bare 28-character token with no "/" at all.
    expect(evidence.file.blob.key).to include("/")
    expect(evidence.file.blob.key).not_to match(/\A[a-z0-9]{20,}\z/i)
  end

  it "keeps the key unguessable despite the structured path" do
    evidence = create(:evidence, authorization_boundary: boundary)
    evidence.file.attach(**upload)

    leaf = evidence.file.blob.key.split("/").last
    expect(leaf.length).to be >= 20
  end

  it "still stores and retrieves the bytes at the new key" do
    evidence = create(:evidence, authorization_boundary: boundary)
    evidence.file.attach(**upload(content: "round-trip me"))

    expect(evidence.file.blob.download).to eq("round-trip me")
  end

  # The case that makes the `new_record?` guard load-bearing. In the default
  # (reference) versioning mode ArtifactVersion#content is attached to the very
  # same blob as Evidence#file. Rewriting an existing blob's key would point the
  # record at an object that does not exist.
  describe "a blob attached to a second record by reference" do
    it "keeps its original key rather than being re-keyed" do
      evidence = create(:evidence, authorization_boundary: boundary)
      evidence.file.attach(**upload)
      original_key = evidence.file.blob.key

      version = ArtifactVersion.create!(evidence: evidence, fingerprint: SecureRandom.hex(8))
      version.content.attach(evidence.file.blob)

      expect(version.content.blob.key).to eq(original_key)
      expect(version.content.blob.download).to eq("hello")
    end
  end

  # An independently-uploaded version DOES build a new blob, so it gets its own
  # version-scoped key — which is what makes per-version Object Lock viable.
  describe "a version with independently uploaded bytes" do
    it "gets its own key nested under the evidence" do
      evidence = create(:evidence, authorization_boundary: boundary)
      evidence.file.attach(**upload)

      version = ArtifactVersion.create!(evidence: evidence, fingerprint: SecureRandom.hex(8))
      version.content.attach(**upload(content: "an independent copy"))

      expect(version.content.blob.key).to include("/evidence/")
      expect(version.content.blob.key).to include("/versions/#{version.id}/")
      expect(version.content.blob.key).not_to eq(evidence.file.blob.key)
    end
  end

  it "does not fail the upload when key derivation raises" do
    # Storage layout must never be the reason a customer cannot upload. The
    # fallback is the old flat key, which is still correct and still readable.
    allow(StorageKeyService).to receive(:key_for).and_raise(StandardError, "boom")
    evidence = create(:evidence, authorization_boundary: boundary)

    expect { evidence.file.attach(**upload) }.not_to raise_error
    expect(evidence.file.blob).to be_present
    expect(evidence.file.blob.download).to eq("hello")
  end
end
