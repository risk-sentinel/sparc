# frozen_string_literal: true

# #830 — inspect and migrate the object-key layout.
#
# ActiveStorage keys are PERSISTED, so relocating a blob is copy-then-update,
# never a rename: the bytes must exist at the new key before the row changes,
# and the old object is only removed once the row points elsewhere. That
# ordering is what makes a partial run safe — a crash leaves a duplicate object,
# which is wasteful but harmless, rather than a database row pointing at nothing.
#
# A mixed layout is therefore a NORMAL state, not a failure: blobs written after
# #830 are structured, blobs written before it are flat, and both are readable
# throughout. `sparc:storage:audit` reports the split so an operator can see
# progress rather than guess at it.
namespace :sparc do
  namespace :storage do
    desc "Report how many blobs use the structured key layout vs the legacy flat one (#830)"
    task audit: :environment do
      total = ActiveStorage::Blob.count
      if total.zero?
        puts "No blobs stored."
        next
      end

      legacy = ActiveStorage::Blob.where.not("key LIKE '%/%'").count
      structured = total - legacy

      puts "Object key layout (#830)"
      puts "  structured : #{structured} (#{percent(structured, total)}%)"
      puts "  legacy flat: #{legacy} (#{percent(legacy, total)}%)"
      puts "  total      : #{total}"

      if legacy.positive?
        puts
        puts "Legacy blobs sit at the bucket root and are NOT covered by prefix-scoped"
        puts "IAM or by lifecycle rules written against sparc/ or an organization prefix."
        puts "Preview a relocation with:  bin/rails sparc:storage:relocate"
        puts "Apply it with:              bin/rails sparc:storage:relocate APPLY=true"
      else
        puts
        puts "Every blob is under the structured layout."
      end

      by_prefix = ActiveStorage::Blob.where("key LIKE '%/%'")
                                     .group(Arel.sql("split_part(key, '/', 1)")).count
      unless by_prefix.empty?
        puts
        puts "Top-level prefixes in use:"
        by_prefix.sort_by { |_, count| -count }.each { |prefix, count| puts "  #{prefix}/ — #{count}" }
      end
    end

    desc "Relocate legacy flat-keyed blobs to the structured layout. DRY RUN unless APPLY=true (#830)"
    task relocate: :environment do
      apply = ENV["APPLY"].to_s.downcase == "true"
      limit = ENV.fetch("LIMIT", "0").to_i

      scope = ActiveStorage::Blob.where.not("key LIKE '%/%'").order(:id)
      scope = scope.limit(limit) if limit.positive?

      puts apply ? "APPLYING relocation." : "DRY RUN — nothing will be changed. Re-run with APPLY=true to apply."
      puts

      moved = skipped = failed = 0

      scope.find_each do |blob|
        attachment = blob.attachments.first
        # An unattached blob has no owner to derive a path from. The existing
        # ArtifactStorageReaperJob already sweeps those; relocating them would
        # be inventing an owner.
        if attachment.nil?
          skipped += 1
          next
        end

        record = attachment.record
        if record.nil?
          skipped += 1
          next
        end

        new_key = StorageKeyService.key_for(record: record, name: attachment.name, token: blob.key)
        if new_key == blob.key
          skipped += 1
          next
        end

        puts "  #{blob.key}  ->  #{new_key}"

        unless apply
          moved += 1
          next
        end

        begin
          relocate_blob!(blob, new_key)
          moved += 1
        rescue StandardError => e
          failed += 1
          warn "  !! #{blob.key}: #{e.class}: #{e.message}"
        end
      end

      puts
      puts "#{apply ? 'Relocated' : 'Would relocate'}: #{moved}   skipped: #{skipped}   failed: #{failed}"
      puts "Skipped blobs are unattached or already structured — see sparc:storage:audit."
    end
  end
end

# Copy first, then repoint the row, then delete the old object. A crash between
# steps one and two leaves an orphan copy (wasteful, harmless); a crash between
# two and three leaves the old object behind (likewise). At no point does a
# persisted row reference a key whose bytes are absent.
def relocate_blob!(blob, new_key)
  service = blob.service
  old_key = blob.key

  service.upload(new_key, StringIO.new(service.download(old_key)), checksum: blob.checksum)
  blob.update_column(:key, new_key)
  service.delete(old_key)
end

def percent(part, total)
  return 0 if total.zero?

  ((part.to_f / total) * 100).round(1)
end
