# frozen_string_literal: true

# #830 — give every newly-created blob a structured key.
#
# ActiveStorage assigns a random 28-character key in a Blob `before_create`, and
# at that moment the blob does NOT know what it is being attached to: the
# attachment row is written afterwards, so `blob.attachments` is empty and a
# Blob-level hook has nothing to derive a path from.
#
# `ActiveStorage::Attached::Changes::CreateOne` is the one place that holds both
# the record and the attachment name while the blob is still being built, so
# patching it here covers every `attach` call site — the eight in app code
# today, and any added later — without threading a key argument through each
# one. CreateMany inherits from CreateOne, so `has_many_attached` is covered by
# the same patch.
#
# ── Why only a NEW blob is renamed ────────────────────────────────────────
#
# `find_or_build_blob` returns an EXISTING blob when one is attached by
# reference rather than uploaded. That is not an edge case here: in the default
# (reference) versioning mode, `ArtifactVersion#content` is attached to the very
# same blob as `Evidence#file`, so one blob has two owners. Its key is already
# persisted and its bytes already live at that path, so rewriting the key would
# point the record at an object that does not exist.
#
# Guarding on `new_record?` makes that correct by construction rather than by
# special-casing: a blob is keyed once, by whoever created it, and every later
# attachment reuses it. Copy-per-version mode uploads independent bytes and
# therefore builds a NEW blob, which correctly receives its own version-scoped
# key — which is what makes per-version Object Lock viable.
#
# Wrapped in `to_prepare` so it survives development reloads, and because
# StorageKeyService is an autoloaded app/ constant that must not be referenced
# at initializer top level.
Rails.application.config.to_prepare do
  ActiveStorage::Attached::Changes::CreateOne.class_eval do
    unless method_defined?(:find_or_build_blob_without_sparc_key)
      alias_method :find_or_build_blob_without_sparc_key, :find_or_build_blob

      def find_or_build_blob
        blob = find_or_build_blob_without_sparc_key
        return blob unless blob.new_record?
        return blob if blob.key.blank? && !blob.respond_to?(:key=)

        # ActiveStorage has already generated the token by this point; it is
        # kept as the leaf so the key stays unguessable while the path in front
        # of it becomes meaningful.
        token = blob.key.presence || ActiveStorage::Blob.generate_unique_secure_token
        blob.key = StorageKeyService.key_for(record: record, name: name, token: token)
        blob
      rescue StandardError => e
        # Storage layout is not worth failing an upload over. A blob that keeps
        # its flat random key is still correct and still readable — it is just
        # unscoped, which the reconciliation task can find later. Loud, because
        # silently reverting to the old layout is how a migration rots.
        Rails.logger.error(
          "[SPARC] structured storage key failed for #{record.class.name}##{record.id} (#{name}): " \
          "#{e.class}: #{e.message}. Falling back to the default flat key."
        )
        blob
      end
    end
  end
end
