# frozen_string_literal: true

# #1176 (owner decision, option A) — a service account's email is a contact,
# not its identity.
#
# A team's group mailbox is often the owner and contact of several service
# accounts, and the unique index on LOWER(email) refused the second one. A
# service account authenticates only with its API token, so its email is never
# looked up to decide who is signing in. A person's email is, so for people it
# stays unique, case-insensitively, at the database.
#
# The replacement index is created before the old one is dropped, so there is
# no moment when people's emails are unconstrained.
#
# `down` restores the old index and fails if service accounts now share an
# email. Rolling back past this point means giving those accounts distinct
# emails first.
class ScopeEmailUniquenessToHumanAccounts < ActiveRecord::Migration[8.1]
  HUMAN_INDEX = "index_users_on_lower_email_human"
  OLD_INDEX = "index_users_on_lower_email"

  def up
    unless index_name_exists?(:users, HUMAN_INDEX)
      add_index :users, "lower((email)::text)", unique: true, name: HUMAN_INDEX,
                where: "service_account = false"
    end
    remove_index :users, name: OLD_INDEX, if_exists: true
  end

  def down
    unless index_name_exists?(:users, OLD_INDEX)
      add_index :users, "lower((email)::text)", unique: true, name: OLD_INDEX
    end
    remove_index :users, name: HUMAN_INDEX, if_exists: true
  end
end
