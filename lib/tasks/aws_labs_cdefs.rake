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
  end
end
