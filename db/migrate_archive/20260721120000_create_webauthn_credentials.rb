# frozen_string_literal: true

# #779 — FIDO2/WebAuthn authenticators. A user may register one or many security
# keys (YubiKey, Feitian, Token2, platform authenticators), each usable
# passwordless (resident credential + PIN) or as a second factor. The private key
# never leaves the authenticator; SPARC stores only the public key, the credential
# id (external_id), and the signature counter — the last of which detects cloned
# keys via counter regression.
#
# users.webauthn_id is the stable per-user WebAuthn user handle (the userHandle a
# discoverable credential returns at usernameless login); nullable + generated
# lazily on first enrollment, so existing users are unaffected.
#
# NIST 800-53: IA-2(1)/(2) MFA, IA-2(8) replay/phishing-resistant, IA-5 authenticator management.
class CreateWebauthnCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :webauthn_id, :string
    add_index  :users, :webauthn_id, unique: true

    create_table :webauthn_credentials do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string   :external_id, null: false          # base64url credential id
      t.string   :public_key,  null: false          # COSE public key (base64)
      t.bigint   :sign_count,  null: false, default: 0
      t.string   :nickname                           # user-facing label
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :webauthn_credentials, :external_id, unique: true
  end
end
