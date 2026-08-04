# #887 — rebuild the CdefComponent browser index.
#
# The rows are pure derivation, so this is always safe to re-run: it replaces
# a document's components rather than merging, and identical input produces
# identical rows.
#
# Region components must be indexed before the services that reference them —
# a service resolves its `provided-by` fragments against already-indexed region
# rows. The ordering below does that. A service indexed too early resolves no
# regions rather than failing, and a second pass corrects it.
namespace :cdef do
  desc "Rebuild the CdefComponent index for all (or one) CDEF document"
  task reindex: :environment do
    only = ENV["CDEF_ID"].presence

    scope = CdefDocument.all
    scope = scope.where(id: only) if only

    # Regions first. `sort_by` rather than SQL ordering so the rule is visible.
    documents = scope.to_a.sort_by { |d| d.name.to_s.match?(/aws_regions/i) ? 0 : 1 }

    indexed = 0
    components = 0
    skipped = []
    failed = []

    documents.each do |document|
      oscal = CdefSourceResolver.new(document).oscal
      if oscal.nil?
        skipped << document.name
        next
      end

      components += CdefComponentIndexer.new(document, oscal).index!
      indexed += 1
    rescue StandardError => e
      failed << "#{document.name}: #{e.class}: #{e.message}"
    end

    puts "[cdef:reindex] documents=#{indexed} components=#{components} " \
         "skipped=#{skipped.size} failed=#{failed.size}"
    puts "[cdef:reindex] no source available: #{skipped.first(10).join(', ')}" if skipped.any?
    failed.first(10).each { |f| warn "[cdef:reindex] FAILED #{f}" }

    abort("[cdef:reindex] #{failed.size} document(s) failed") if failed.any?
  end
end
