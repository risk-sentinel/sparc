# frozen_string_literal: true

# #1259 — record which built-in role values an instance administrator has set,
# so the roles seed section stops overwriting them.
#
# Adds `roles.admin_overrides` (`{ key => shipped default when recorded }`; see
# Role#record_admin_choices and BuiltInRoleSeeder), then records the choices an
# existing install already holds.
#
# An administrator's past edits cannot be told apart from the defaults they
# replaced, so ANY current difference from what the roles section last applied
# is treated as the administrator's choice, recorded, and written to the audit
# trail (`role_override_recorded`). "What the section last applied" is the
# frozen snapshot in db/data/built_in_role_defaults_roles_1_4_0.json — the
# defaults of roles section 1.4.0, which every supported install (v1.16.3 and
# later) has run. It is NOT read from BuiltInRoles: those defaults move with
# every release, and comparing against a newer release's defaults would record
# each default that release changes as an administrator override and so stop it
# from ever arriving.
#
# One more signal is available, for a key whose shipped default has changed
# since that snapshot. The seeds only ever wrote GRANTED keys; the role editor
# and the API write every key, `false` included. So a key that is present in a
# role's permissions with the value the snapshot also had was last written by
# an administrator's save, and is kept as their choice instead of being moved
# to the new default (#1257: an administrator who already set Policy Manager's
# `cdef.write` either way keeps it). The limit: a save that changed only, say,
# the description also wrote that key, so it counts as the administrator's too.
#
# Runs synchronously, not as a deferred data migration: the entrypoint runs
# db:seed straight after db:prepare, and the roles section must find these
# overrides already recorded or it would apply the new defaults over them. It
# touches at most one row per built-in role.
#
# Idempotent: a key already recorded is left alone, so a second run records and
# audits nothing, and a run stopped part-way resumes with the roles it missed.
class AddAdminOverridesToRoles < ActiveRecord::Migration[8.1]
  BASELINE = Rails.root.join("db/data/built_in_role_defaults_roles_1_4_0.json")

  def up
    unless column_exists?(:roles, :admin_overrides)
      add_column :roles, :admin_overrides, :jsonb, default: {}, null: false
    end
    Role.reset_column_information

    recorded = record_existing_choices
    say "Recorded #{recorded} administrator override(s) on built-in roles"
  end

  def down
    remove_column :roles, :admin_overrides, if_exists: true
    Role.reset_column_information
  end

  private

  def baseline
    @baseline ||= JSON.parse(BASELINE.read).index_by { |entry| entry["name"] }
  end

  def record_existing_choices
    recorded = 0
    Role.where(name: baseline.keys).find_each do |role|
      found = choices_for(role, baseline[role.name])
      next if found.empty?

      role.update_columns(admin_overrides: role.admin_overrides.to_h.merge(found.transform_values { |v| v[:shipped] }))
      found.each { |key, values| audit(role, key, values) }
      recorded += found.size
    end
    recorded
  end

  # { key => { value:, shipped: } } for each key that holds an administrator's
  # choice and is not recorded yet.
  def choices_for(role, entry)
    stored = role.permissions.to_h
    found = {}

    Role::PERMISSION_KEYS.each do |key|
      next if role.admin_overridden?(key)

      shipped = entry["permissions"].include?(key)
      value = stored[key] == true
      default_moved = Role.comparable(key, BuiltInRoles.default_for(role.name, key)) != shipped
      next unless value != shipped || (stored.key?(key) && default_moved)

      found[key] = { value: value, shipped: shipped }
    end

    BuiltInRoles::ATTRIBUTES.each do |key|
      next if role.admin_overridden?(key)

      shipped = Role.comparable(key, entry[key])
      value = Role.comparable(key, role.public_send(key))
      found[key] = { value: value, shipped: shipped } if value != shipped
    end

    found
  end

  def audit(role, key, values)
    AuditEvent.log(action: "role_override_recorded", subject: role,
                   metadata: { role_name: role.name, key: key, value: values[:value],
                               shipped: values[:shipped], source: "upgrade" })
  end
end
