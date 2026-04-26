require "rails_helper"

RSpec.describe AuthoritativeSourceFederationService do
  let(:peer) do
    FederationPeer.create!(name: "Source", base_url: "https://source.example.gov",
                           signing_secret: "a" * 32, service_token: "bearer-token-xyz")
  end
  let(:actor) { create(:user, :admin) }

  def make_authoritative_resource(title:)
    BackMatterResource.create!(
      uuid:                SecureRandom.uuid,
      title:               title,
      source:              "authoritative",
      globally_available:  true,
      promotion_status:    "approved",
      href:                "https://example.gov/policy.pdf",
      media_type:          "application/pdf"
    )
  end

  describe ".build_export_bundle" do
    it "produces a signed envelope containing only authoritative resources" do
      make_authoritative_resource(title: "Policy A")
      BackMatterResource.create!(uuid: SecureRandom.uuid, title: "Managed",
                                 source: "managed",
                                 resourceable: create(:ssp_document))

      envelope = described_class.build_export_bundle(peer: peer)
      verification = FederationBundleSigningService.verify(envelope, peer: peer)
      expect(verification).to be_success
      payload = verification.payload

      titles = payload["resources"].map { |r| r["title"] }
      expect(titles).to eq([ "Policy A" ])
      expect(payload.dig("metadata", "instance_url")).to be_present
      expect(payload.dig("metadata", "resource_count")).to eq(1)
    end

    it "filters by `since` when provided" do
      old = make_authoritative_resource(title: "Old")
      old.update_columns(updated_at: 2.days.ago)
      make_authoritative_resource(title: "Recent")

      envelope = described_class.build_export_bundle(peer: peer, since: 1.day.ago)
      payload  = FederationBundleSigningService.verify(envelope, peer: peer).payload

      expect(payload["resources"].map { |r| r["title"] }).to eq([ "Recent" ])
    end

    it "excludes archived resources" do
      r = make_authoritative_resource(title: "Archived")
      r.update!(archived_at: 1.day.ago)

      envelope = described_class.build_export_bundle(peer: peer)
      payload  = FederationBundleSigningService.verify(envelope, peer: peer).payload

      expect(payload["resources"]).to be_empty
    end
  end

  describe ".import_bundle" do
    let(:source_resource) { make_authoritative_resource(title: "Imported Policy") }

    it "imports resources from a valid bundle, marking them federated" do
      source_resource # ensure exists in source BEFORE we build the bundle
      envelope = described_class.build_export_bundle(peer: peer)

      # Pretend the envelope arrived from a remote and our DB has no record yet.
      payload = FederationBundleSigningService.verify(envelope, peer: peer).payload
      remote_uuid = payload["resources"].first["uuid"]
      BackMatterResource.find_by(uuid: remote_uuid)&.destroy!

      result = described_class.import_bundle(envelope, peer: peer, actor: actor)

      expect(result).to be_success
      expect(result.imported.size).to eq(1)
      imported = result.imported.first
      expect(imported.source).to eq("authoritative")
      expect(imported.globally_available).to eq(true)
      expect(imported.federated_from_instance).to be_present
      expect(imported.original_uuid).to eq(remote_uuid)
      expect(imported.federated_bundle_uuid).to eq(payload.dig("metadata", "bundle_uuid"))

      change = imported.changes_log.find_by(change_type: "federate")
      expect(change).to be_present
      expect(change.changed_by_user).to eq(actor)
    end

    it "skips duplicates on a second import (dedup by federated_from_instance + original_uuid)" do
      source_resource
      envelope = described_class.build_export_bundle(peer: peer)
      payload  = FederationBundleSigningService.verify(envelope, peer: peer).payload
      BackMatterResource.find_by(uuid: payload["resources"].first["uuid"])&.destroy!

      first  = described_class.import_bundle(envelope, peer: peer, actor: actor)
      second = described_class.import_bundle(envelope, peer: peer, actor: actor)

      expect(first.imported.size).to eq(1)
      expect(second.imported.size).to eq(0)
      expect(second.skipped.size).to eq(1)
    end

    it "returns an error result when signature does not verify" do
      envelope = described_class.build_export_bundle(peer: peer).merge("signature" => "0" * 64)
      result   = described_class.import_bundle(envelope, peer: peer, actor: actor)

      expect(result).not_to be_success
      expect(result.error).to match(/Signature verification failed/i)
    end

    it "updates the peer last_synced_at on success" do
      source_resource
      envelope = described_class.build_export_bundle(peer: peer)
      payload  = FederationBundleSigningService.verify(envelope, peer: peer).payload
      BackMatterResource.find_by(uuid: payload["resources"].first["uuid"])&.destroy!

      described_class.import_bundle(envelope, peer: peer, actor: actor)
      peer.reload
      expect(peer.last_synced_at).to be_within(5.seconds).of(Time.current)
      expect(peer.last_sync_status).to eq("success")
    end
  end

  describe ".pull" do
    let(:remote_peer) do
      FederationPeer.create!(name: "Remote", base_url: "https://remote.example.gov",
                             signing_secret: "b" * 32, service_token: "remote-bearer")
    end

    it "fails fast for a disabled peer" do
      remote_peer.update!(enabled: false)
      result = described_class.pull(peer: remote_peer, actor: actor)
      expect(result).not_to be_success
      expect(result.error).to match(/disabled/i)
    end

    it "fails fast when the peer has no service_token" do
      remote_peer.update!(encrypted_service_token: nil)
      result = described_class.pull(peer: remote_peer, actor: actor)
      expect(result).not_to be_success
      expect(result.error).to match(/no service_token/i)
    end

    it "imports a remote bundle on a successful HTTP fetch" do
      make_authoritative_resource(title: "Federated Policy")
      bundle = described_class.build_export_bundle(peer: remote_peer)
      payload = FederationBundleSigningService.verify(bundle, peer: remote_peer).payload
      BackMatterResource.find_by(uuid: payload["resources"].first["uuid"])&.destroy!

      stub_response = instance_double(Net::HTTPOK, is_a?: false, body: bundle.to_json, code: "200")
      allow(stub_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(described_class).to receive(:http_get_export).and_return(stub_response)

      result = described_class.pull(peer: remote_peer, actor: actor)
      expect(result).to be_success
      expect(result.imported.size).to eq(1)
    end

    it "records a failed pull when the peer responds with non-2xx" do
      stub_response = instance_double(Net::HTTPNotFound, is_a?: false, code: "404", body: "")
      allow(stub_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(described_class).to receive(:http_get_export).and_return(stub_response)

      result = described_class.pull(peer: remote_peer, actor: actor)
      expect(result).not_to be_success
      expect(remote_peer.reload.last_sync_status).to match(/fetch_error/)
    end

    it "records a parse error on invalid JSON" do
      stub_response = instance_double(Net::HTTPOK, is_a?: false, body: "not json", code: "200")
      allow(stub_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(described_class).to receive(:http_get_export).and_return(stub_response)

      result = described_class.pull(peer: remote_peer, actor: actor)
      expect(result).not_to be_success
      expect(remote_peer.reload.last_sync_status).to eq("parse_error")
    end
  end
end
