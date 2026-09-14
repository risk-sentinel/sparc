# #841 — an admin-initiated password reset needs somewhere to keep the
# challenge. Only the DIGEST is stored, never the token itself, matching how
# ApiToken has always handled this (IA-5: no plaintext authenticator at rest).
#
# The token is single-use and expiring, so both columns are cleared the moment
# it is redeemed. A NULL digest means "no reset outstanding".
class AddPasswordResetToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :password_reset_digest, :string
    add_column :users, :password_reset_expires_at, :datetime

    # Redemption looks the user up BY the digest, so this index is on the read
    # path of an unauthenticated endpoint. Partial: only rows with an
    # outstanding reset are ever matched.
    add_index :users, :password_reset_digest, unique: true,
              where: "password_reset_digest IS NOT NULL",
              name: "index_users_on_password_reset_digest"
  end
end
