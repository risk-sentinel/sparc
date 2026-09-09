# Issue #466 — Manual import trigger for AWS Labs CDEFs. Useful for first
# run, operator-driven refreshes, and air-gapped mirror testing.
#
# Usage:
#   bin/rails aws_labs:cdefs:import          # respects ETag cache
#   bin/rails 'aws_labs:cdefs:import[true]'  # force refetch (ignore ETag)
namespace :aws_labs do
  namespace :cdefs do
    desc "Import AWS Labs CDEFs (pass [true] to force-refetch ignoring ETag cache)"
    task :import, [ :force ] => :environment do |_t, args|
      force = ActiveModel::Type::Boolean.new.cast(args[:force])

      unless SparcConfig.aws_labs_cdef_enabled?
        warn "SPARC_AWS_LABS_CDEF_ENABLED is not set to 'true' — aborting."
        warn "Set the env var before running this task in production."
        exit 1
      end

      puts "[aws_labs:cdefs:import] force=#{force}"
      puts "  repo:    #{SparcConfig.aws_labs_cdef_repo}"
      puts "  branch:  #{SparcConfig.aws_labs_cdef_branch}"
      puts "  oscal:   #{Array(SparcConfig.aws_labs_oscal_versions).join(', ').presence || '(all)'}"
      puts "  token:   #{SparcConfig.aws_labs_github_token.present? ? '(set)' : '(none)'}"

      result = AwsLabsCdefImportService.new.run(force: force)
      puts "[aws_labs:cdefs:import] #{result}"

      if result.errors.any?
        puts "Errors:"
        result.errors.each { |e| puts "  - #{e[:path]}: #{e[:error]}" }
        exit 1
      end
    end

    # #1088 — recover component attribution and control-implementation sources
    # on AWS Labs CDEFs that were imported before the parser kept them.
    #
    # The work is in `AwsLabsCdefImportService#reparse_existing!`, which parses
    # onto the EXISTING record. It deliberately does not go through the normal
    # import path: that one supersedes and re-creates, which is right for
    # genuinely changed upstream content and duplicates the entire corpus when
    # used for a re-parse.
    desc "Re-parse AWS Labs CDEFs already imported, recovering component attribution (#1088)"
    task :reparse, [ :all ] => :environment do |_t, args|
      unless SparcConfig.aws_labs_cdef_enabled?
        warn "SPARC_AWS_LABS_CDEF_ENABLED is not set to 'true' — aborting."
        exit 1
      end

      # Default: only documents that have no attribution yet. Pass [true] to
      # re-parse every AWS Labs document regardless.
      only_missing = !ActiveModel::Type::Boolean.new.cast(args[:all])
      puts "[aws_labs:cdefs:reparse] only_missing_attribution=#{only_missing}"

      before = CdefDocument.count
      result = AwsLabsCdefImportService.new.reparse_existing!(only_missing_attribution: only_missing)
      after  = CdefDocument.count

      puts "[aws_labs:cdefs:reparse] eligible=#{result[:eligible]} reparsed=#{result[:reparsed]} errors=#{result[:errors].size}"
      puts "[aws_labs:cdefs:reparse] cdef_documents #{before} -> #{after} (must be unchanged)"
      puts "[aws_labs:cdefs:reparse] controls with attribution: " \
           "#{CdefControl.where.not(component_uuid: [ nil, '' ]).count}"

      if after != before
        warn "Document count CHANGED — a re-parse must never create documents."
        exit 1
      end

      if result[:errors].any?
        puts "Errors:"
        result[:errors].each { |e| puts "  - #{e[:path]}: #{e[:error]}" }
        exit 1
      end
    end
  end
end
