# #395 P3: one-shot rake task to re-derive document metadata from
# their AuthorizationBoundary for legacy data. Idempotent — only updates
# documents whose values differ from the boundary.
#
# Usage:
#   bundle exec rake boundary:resync
#
namespace :boundary do
  desc "Re-derive document metadata from each boundary (#395 P3)"
  task resync: :environment do
    total_boundaries = 0
    total_documents  = 0
    total_updates    = 0

    AuthorizationBoundary.find_each do |boundary|
      result = BoundaryMetadataSyncService.new(boundary).propagate!
      total_boundaries += 1
      total_documents  += result.size
      total_updates    += result.values.sum
      puts "boundary=#{boundary.id} (#{boundary.name}) updated_per_doc=#{result.values.sum} docs=#{result.size}"
    end

    puts ""
    puts "boundary:resync complete -- #{total_boundaries} boundaries, #{total_documents} documents, #{total_updates} field updates"
  end
end
