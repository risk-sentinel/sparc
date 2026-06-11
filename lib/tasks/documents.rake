# #618 — operational cleanup for documents stranded in `pending`.
#
# The root cause (API metadata-only creates never resolving) is fixed in code,
# and StuckDocumentReaperJob self-heals going forward. This task is the
# run-once-in-prod lever to clear the existing backlog immediately rather than
# waiting for the reaper's next tick.
#
# Idempotent: only touches fileless documents still in `pending`, so re-running
# is a no-op. Safe to run read-only first with DRY_RUN=true.
#
#   bin/rails documents:resolve_stuck DRY_RUN=true   # report only
#   bin/rails documents:resolve_stuck                # apply
namespace :documents do
  desc "Resolve fileless documents stuck in `pending` to `completed` (#618). DRY_RUN=true to preview."
  task resolve_stuck: :environment do
    dry_run = ENV["DRY_RUN"].to_s.downcase == "true"
    total = 0

    DocumentTypeRegistry::TYPES.each do |type_key, entry|
      klass = entry.document_class
      next unless klass.column_names.include?("status")

      klass.where(status: "pending").find_each do |doc|
        next if doc.respond_to?(:file) && doc.file.attached? # real parse — leave for the reaper

        total += 1
        if dry_run
          puts "[dry-run] would complete #{type_key} ##{doc.id} (#{doc.try(:slug) || doc.try(:name)})"
        else
          doc.update!(status: "completed")
          puts "completed #{type_key} ##{doc.id} (#{doc.try(:slug) || doc.try(:name)})"
        end
      end
    end

    puts(dry_run ? "DRY RUN — #{total} fileless pending document(s) would be completed." \
                 : "Done — #{total} fileless pending document(s) resolved to completed.")
  end
end
