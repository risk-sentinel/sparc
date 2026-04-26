class AddSigningSecretToFederationPeers < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:federation_peers, :encrypted_signing_secret)
      add_column :federation_peers, :encrypted_signing_secret, :text
    end

    unless column_exists?(:federation_peers, :public_metadata)
      # Stores non-sensitive peer metadata (description, contact email,
      # signing-key fingerprint hint) used by the discovery / peer-list UI.
      add_column :federation_peers, :public_metadata, :jsonb,
                 default: {}, null: false
    end
  end
end
