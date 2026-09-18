# #947 — an attestation names a person, but named nothing checkable.
#
# `attester_name` / `attester_email` are free strings with no reference to an
# account, so nothing could confirm the person named actually holds the role
# they attested under, on the boundary the evidence belongs to. For a record
# whose whole substance is *who asserted it*, that is the defect.
#
# This adds the reference. It does NOT replace `attester_name`: per the #934
# rule, the name stays as the snapshot taken at attestation time so a later
# rename or role change never rewrites what the record said when it was signed.
#
# Nullable on purpose. Existing rows predate the reference and cannot be
# resolved automatically — an `attester_name` string is not reliably a person.
# They stay readable, and `Attestation`'s validation is what requires a resolved
# attester on the next write. Backfilling a guess into a non-repudiation record
# would be worse than leaving it honestly empty.
#
# NIST 800-53: AU-10 (non-repudiation), AC-3 (access enforcement), IA-2.
class AddAttesterUserToAttestations < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:attestations, :attester_user_id)
      add_column :attestations, :attester_user_id, :bigint
    end

    unless index_exists?(:attestations, :attester_user_id)
      add_index :attestations, :attester_user_id, if_not_exists: true
    end

    return if foreign_key_exists?(:attestations, :users, column: :attester_user_id)

    # `nullify` rather than `cascade`: deleting a user must never delete the
    # attestations they signed. The signed record outlives the account, which is
    # the point of an audit trail — the snapshot in `attester_name` is what
    # keeps it readable afterwards.
    add_foreign_key :attestations, :users, column: :attester_user_id, on_delete: :nullify
  end

  def down
    if foreign_key_exists?(:attestations, :users, column: :attester_user_id)
      remove_foreign_key :attestations, :users, column: :attester_user_id
    end
    remove_index :attestations, :attester_user_id, if_exists: true
    remove_column :attestations, :attester_user_id, if_exists: true
  end
end
