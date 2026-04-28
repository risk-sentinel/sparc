require "rails_helper"
require "rake"

RSpec.describe "lib/tasks/reencrypt.rake", type: :task do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  let(:task) { Rake::Task["sparc:reencrypt:rotate_master_key"] }
  let(:old_master) { "y" * 48 }

  before do
    task.reenable
    ENV["OLD_SPARC_HASH"] = old_master
  end

  after { ENV.delete("OLD_SPARC_HASH") }

  def peer_under_old_master(name:)
    peer = FederationPeer.create!(name: name, base_url: "https://#{name.parameterize}.example.gov")
    enc = FederationPeer.build_encryptor_with_master(old_master, FederationPeer::TOKEN_KEY_PURPOSE)
    peer.update_column(:encrypted_service_token, enc.encrypt_and_sign("rotateable-token"))
    peer
  end

  it "writes a sparc_hash_rotated AuditEvent with rotation counts on success" do
    peer_under_old_master(name: "Audited")

    expect {
      task.invoke
    }.to change { AuditEvent.where(action: "sparc_hash_rotated").count }.by(1)

    audit = AuditEvent.where(action: "sparc_hash_rotated").last
    expect(audit.metadata["rotated_count"]).to eq(1)
    expect(audit.metadata["skipped_count"]).to eq(0)
    expect(audit.metadata["old_hash_fingerprint"].length).to eq(16)
    expect(audit.metadata["new_hash_fingerprint"].length).to eq(16)
    expect(audit.metadata["old_hash_fingerprint"]).not_to eq(audit.metadata["new_hash_fingerprint"])
  end

  it "aborts the rake when OLD_SPARC_HASH is unset" do
    ENV.delete("OLD_SPARC_HASH")
    expect { task.invoke }.to raise_error(SystemExit)
  end
end
