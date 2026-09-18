# frozen_string_literal: true

# #1116 — resolve the `role-id`s that free text produced.
#
# ── What went wrong ────────────────────────────────────────────────────────
#
# #1100 made statement **Responsible Roles** editable as a comma-separated
# string of role ids, and nothing validated what was typed. An author typing
# `isso` minted a private id for a role NIST already defines as
# `information-system-security-officer`; an author typing `System Owner` minted
# a second spelling of a role the document already declares.
#
# Either way the exported document is SCHEMA-VALID and still wrong — a
# `responsible-role` whose `role-id` references nothing in `metadata.roles`.
# That is a REFERENTIAL break, which is why `OscalSchemaValidationService` never
# caught it and why `OscalConformanceService` (`role-id-unresolved`) had to.
#
# The picker, the declarable-roles surface and the conformance check all shipped
# in PR #1130. This is the last piece: the values already in the database.
#
# ── The rule, per value ────────────────────────────────────────────────────
#
# Nothing is silently dropped. Every stored id takes exactly one of four routes:
#
#   1. It already resolves to a role the document declares  → left alone.
#   2. Its FORM normalises onto a declared role             → reference rewritten.
#      ("System Owner", "system_owner" → `system-owner`)
#   3. It normalises onto a role NIST SUGGESTS for the       → role declared,
#      document's OSCAL version                                reference rewritten.
#   4. Anything else                                         → declared as an
#      ORGANIZATION-DEFINED role, keeping the author's id and their text as the
#      title. A custom role is legal OSCAL — NIST sets `allow-other="yes"` on
#      `responsible-role/@role-id` — it just has to be DECLARED.
#
# Route 4 is the default on purpose. Guessing which NIST role an unrecognised
# string meant would invent a claim the author never made; declaring it makes
# the document conformant without changing what it says.
#
# A `role-id` holding no id at all — blank, or punctuation like "---" — is the
# one thing removed rather than resolved. It is not a reference to anything, and
# `role-id` is required at every site. The count is reported, not swallowed.
class ResolveFreeTextResponsibleRoles < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  # Acronyms authors typed for a role NIST already names — the exact case #1116
  # records. Honoured ONLY when the target is in NIST's suggested vocabulary for
  # THAT document's version (checked at run time), so a NIST rename makes the
  # alias fall through to route 4 instead of minting a reference that resolves
  # to nothing.
  #
  # Deliberately tiny. `issm` has no NIST id and stays organization-defined;
  # `poc` is ambiguous across NIST's three (`system-poc-management`,
  # `-technical`, `-other`) and a migration does not get to pick.
  ALIASES = {
    "isso" => "information-system-security-officer",
    "ao"   => "authorizing-official"
  }.freeze

  def up
    defer_data_migration { resolve_free_text_roles }
  end

  def down
    # Deliberately empty. The prior values were dangling references; there is
    # nothing worth restoring, and the ids themselves survive — route 4 keeps
    # them, as declared roles. (The comment is INSIDE the method on purpose:
    # Sonar's empty-function rule does not read the one above it, and six
    # existing migrations are flagged for exactly that.)
  end

  # Public so the spec drives it directly rather than through the deferral
  # plumbing, which `deferred_data_migration_contract_spec` already covers.
  def resolve_free_text_roles
    totals = Hash.new(0)

    SspDocument.find_each(batch_size: 100) { |doc| tally(totals, resolve_document(doc)) }

    say "responsible roles: #{totals[:rewritten]} references rewritten, " \
        "#{totals[:declared]} roles declared, #{totals[:dropped]} empty ids removed, " \
        "across #{totals[:documents]} document(s)"
  end

  private

  def tally(totals, counts)
    return if counts.nil?

    totals[:documents] += 1
    counts.each { |k, v| totals[k] += v }
  end

  # Returns nil when the document needed nothing, so it is not counted as
  # touched — and, more importantly, so a document that has never authored
  # `metadata.roles` keeps declaring the defaults implicitly.
  def resolve_document(doc)
    suggested = suggested_ids_for(doc)
    # Grows as roles are declared, so two statements naming the same unknown
    # role declare it once.
    known     = doc.declared_role_ids.to_set
    new_roles = []
    counts    = Hash.new(0)

    role_bearing_records(doc).each do |record|
      entries = Array(record.responsible_roles_data)
      next if entries.blank?

      resolved = entries.filter_map do |entry|
        resolve_entry(entry, known: known, suggested: suggested, new_roles: new_roles, counts: counts)
      end.uniq

      next if resolved == entries

      record.update_columns(responsible_roles_data: resolved)
      counts[:rewritten] += 1
    end

    return nil if new_roles.empty? && counts[:rewritten].zero?

    if new_roles.any?
      # `declared_roles`, not `oscal_roles` — a document that has authored no
      # roles still DECLARES the defaults on export, and reading only the
      # authored list would drop them the moment we add the first custom one.
      merged = (doc.metadata_extra || {}).merge("roles" => doc.declared_roles + new_roles)
      doc.update_columns(metadata_extra: merged)
      counts[:declared] += new_roles.size
    end

    counts
  end

  # A document may declare an OSCAL version we ship no conformance dataset for
  # (an import from 1.0.x, say). Falling back to the default is right: the
  # suggested vocabulary is used to RECOGNISE an id, and recognising fewer would
  # only push a role NIST names onto route 4 as organization-defined.
  def suggested_ids_for(doc)
    version = doc.oscal_version.presence || OscalSchema::DEFAULT_VERSION
    ids     = OscalRole.suggested_ids(version)
    ids     = OscalRole.suggested_ids(OscalSchema::DEFAULT_VERSION) if ids.empty?
    ids.to_set
  end

  def role_bearing_records(doc)
    [
      SspControlStatement.joins(:ssp_control).where(ssp_controls: { ssp_document_id: doc.id }),
      SspComponent.where(ssp_document_id: doc.id),
      SspByComponent.joins(:ssp_control).where(ssp_controls: { ssp_document_id: doc.id })
    ].flat_map(&:to_a)
  end

  # Returns the entry to keep, or nil to remove it.
  def resolve_entry(entry, known:, suggested:, new_roles:, counts:)
    # A bare string is the shape the pre-#1100 permit (`responsible_roles_data:
    # []`, an array of scalars) would have written. It exports as
    # `"responsible-roles": ["isso"]`, which is schema-invalid — so it is given
    # the assembly shape on the way past rather than left to fail validation.
    entry = { "role-id" => entry } if entry.is_a?(String)
    return nil unless entry.is_a?(Hash)

    raw = entry["role-id"].to_s.strip
    return entry if known.include?(raw)

    # Blank, or "---": there is no id in it to resolve or declare. `role-id` is
    # required at every site, so the entry is not a reference to anything.
    id = canonical_id(raw)
    if id.nil?
      counts[:dropped] += 1
      return nil
    end

    aliased = ALIASES[id]
    id = aliased if aliased && suggested.include?(aliased)

    unless known.include?(id)
      new_roles << role_for(id, raw, suggested)
      known << id
    end

    entry.merge("role-id" => id)
  end

  def role_for(id, raw, suggested)
    return { "id" => id, "title" => OscalRole.humanize(id) } if suggested.include?(id)

    OscalRole.organization_defined(id, title_for(raw, id))
  end

  # A typed phrase becomes the title verbatim — "Policy Department" is what its
  # author called it, and humanising the derived id would only round-trip it.
  # A token that was already id-shaped gets the same humanisation the picker
  # shows everywhere else.
  def title_for(raw, id)
    raw.match?(/\s/) ? raw.squeeze(" ") : OscalRole.humanize(id)
  end

  # Normalise the FORM of an id, never its vocabulary. `role-id` is an NCName
  # token: it may not start with a digit, and NIST's whole suggested vocabulary
  # is lowercase-hyphen, so that is the form a match has to be made in.
  def canonical_id(raw)
    id = raw.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    return nil if id.blank?

    id.match?(/\A\d/) ? "role-#{id}" : id
  end
end
