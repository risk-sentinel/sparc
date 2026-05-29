# frozen_string_literal: true

# #593 — Enforce case-insensitive uniqueness of users.email at the DATABASE
# layer.
#
# Background: User#normalize_email downcases emails before validation and the
# model declares `uniqueness: { case_sensitive: false }`, but the underlying
# unique index was on the RAW email string. That left a security gap: the
# application-level uniqueness check is not atomic (races), and direct writes
# (update_column, insert_all, raw SQL) bypass it entirely. With both local
# login and OIDC enabled, a user could end up with two accounts differing only
# by letter case (e.g. Jane.Doe@x.com vs jane.doe@x.com) and work around the
# intended one-identity-per-email mapping.
#
# Fix: backfill any legacy mixed-case rows to lowercase, then replace the
# raw-email unique index with a functional unique index on LOWER(email) so the
# database itself rejects case-variant duplicates regardless of code path.
#
# NIST 800-53: IA-4 (Identifier Management), AC-2 (Account Management).
class EnforceCaseInsensitiveUniqueEmail < ActiveRecord::Migration[8.1]
  LOWER_INDEX = "index_users_on_lower_email"

  def up
    # 1. Pre-flight: detect pre-existing case-insensitive collisions. We do NOT
    #    auto-merge accounts (destructive, FK-heavy) — fail fast with an
    #    actionable message so an operator resolves them before the constraint
    #    is applied. In practice normalize_email + downcased OIDC auto-create
    #    mean production should have none.
    dupes = select_all(<<~SQL).to_a
      SELECT LOWER(email) AS key, array_agg(id ORDER BY id) AS ids
      FROM users
      GROUP BY LOWER(email)
      HAVING COUNT(*) > 1
    SQL

    if dupes.any?
      details = dupes.map { |r| "#{r['key']} -> user ids #{r['ids']}" }.join("; ")
      raise <<~MSG
        Cannot enforce case-insensitive email uniqueness: #{dupes.size} email(s)
        have case-variant duplicate accounts. Resolve (merge/deactivate) these
        before deploying #593:
          #{details}
      MSG
    end

    # 2. Backfill legacy mixed-case rows. Safe now — step 1 proved no collisions.
    execute("UPDATE users SET email = LOWER(email) WHERE email <> LOWER(email)")

    # 3. Swap the raw-email unique index for a case-insensitive functional one.
    remove_index :users, name: "index_users_on_email", if_exists: true
    unless index_name_exists?(:users, LOWER_INDEX)
      add_index :users, "LOWER(email)", unique: true, name: LOWER_INDEX
    end
  end

  def down
    remove_index :users, name: LOWER_INDEX, if_exists: true
    unless index_name_exists?(:users, "index_users_on_email")
      add_index :users, :email, unique: true, name: "index_users_on_email"
    end
  end
end
