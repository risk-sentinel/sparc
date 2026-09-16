# frozen_string_literal: true

# #1134 — resolve the `role-ids` that `import_boundary_users` left dangling.
#
# ── What went wrong ────────────────────────────────────────────────────────
#
# `import_boundary_users` (#737) wrote each boundary member's raw membership
# role into `SspUser#role_ids_data` — `authorizing_official`, underscored, which
# is not even NIST's form, and never declared in `metadata.roles`. Every export
# from a boundary with members carried a `system-implementation.users[].role-ids`
# that referenced nothing.
#
# The import now declares what it references. This is the values already in the
# database. It is the sibling of `ResolveFreeTextResponsibleRoles` (#1116), which
# handled statement responsible-roles — a different column reached by a
# different path.
#
# ── The rule, per value ────────────────────────────────────────────────────
#
# Nothing is silently dropped. Every stored id takes exactly one of four routes:
#
#   1. It already resolves to a role the document declares  → left alone.
#   2. It is a boundary-membership role — what the import   → resolved through
#      wrote                                                   `declare_membership_roles`,
#                                                              the same path the
#                                                              import uses now.
#   3. Its FORM normalises onto a declared role, or one NIST → reference rewritten,
#      suggests for the document's version                    NIST role declared.
#   4. Anything else                                         → declared as an
#      ORGANIZATION-DEFINED role under its normalised id.
#
# Route 2 comes before 3 on purpose: it is the one that knows `isso` means NIST's
# `information-system-security-officer`, and it is exactly the resolution a fresh
# import would produce — so a migrated document and a re-imported one agree.
#
# A value holding no id at all — blank, or punctuation — is removed rather than
# resolved; it is not a reference to anything. The count is reported.
class ResolveSystemUserRoleIds < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration { resolve_system_user_role_ids }
  end

  def down
    # Deliberately empty. The prior values were dangling references; nothing
    # worth restoring, and route 4 keeps every unrecognised id as a declared
    # role. (Inside the method so Sonar's empty-function rule reads it.)
  end

  # Public so the spec drives it directly rather than through the deferral
  # plumbing, which `deferred_data_migration_contract_spec` already covers.
  def resolve_system_user_role_ids
    totals = Hash.new(0)

    SspDocument.where(id: SspUser.select(:ssp_document_id)).find_each(batch_size: 100) do |doc|
      counts = resolve_document(doc)
      next if counts.nil?

      totals[:documents] += 1
      counts.each { |k, v| totals[k] += v }
    end

    say "system user role-ids: #{totals[:rewritten]} users rewritten, " \
        "#{totals[:declared]} roles declared, #{totals[:dropped]} empty ids removed, " \
        "across #{totals[:documents]} document(s)"
  end

  private

  # Returns nil when the document needed nothing, so it is not counted — and so
  # a document that never authored `metadata.roles` keeps declaring the defaults
  # implicitly.
  def resolve_document(doc)
    declared_before = doc.declared_role_ids.size
    counts = Hash.new(0)

    doc.ssp_users.each do |user|
      ids = Array(user.role_ids_data)
      next if ids.empty?

      resolved = ids.filter_map { |raw| resolve_id(doc, raw, counts) }.uniq
      next if resolved == ids

      user.update_columns(role_ids_data: resolved)
      counts[:rewritten] += 1
    end

    declared = doc.declared_role_ids.size - declared_before
    return nil if declared.zero? && counts[:rewritten].zero? && counts[:dropped].zero?

    # `metadata_extra` is only dirty if a route declared something; the in-memory
    # assignment came from `oscal_roles=`, which keeps the implicit defaults.
    doc.update_columns(metadata_extra: doc.metadata_extra) if declared.positive?
    counts[:declared] += declared
    counts
  end

  # Returns the id to keep, or nil to remove it.
  def resolve_id(doc, raw, counts)
    value = raw.to_s.strip
    return value if doc.declared_role_ids.include?(value)

    # Route 2 — the membership vocabulary, in whatever form the import stored it.
    membership = value.downcase.tr("-", "_")
    if AuthorizationBoundaryMembership.acceptable_roles.include?(membership)
      return doc.declare_membership_roles([ membership ]).fetch(membership)
    end

    id = canonical_id(value)
    if id.nil?
      counts[:dropped] += 1
      return nil
    end
    return id if doc.declared_role_ids.include?(id)

    # Routes 3 and 4.
    role = if OscalRole.suggested_ids(doc.role_vocabulary_version).include?(id)
             { "id" => id, "title" => OscalRole.humanize(id) }
    else
             OscalRole.organization_defined(id, value.match?(/\s/) ? value.squeeze(" ") : OscalRole.humanize(id))
    end
    doc.oscal_roles = doc.declared_roles + [ role ]
    id
  end

  # FORM, never vocabulary — the same normalisation `ResolveFreeTextResponsibleRoles`
  # applies, copied rather than shared so neither migration changes under the
  # other. `role-id` is an NCName and may not start with a digit.
  def canonical_id(raw)
    id = raw.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    return nil if id.blank?

    id.match?(/\A\d/) ? "role-#{id}" : id
  end
end
