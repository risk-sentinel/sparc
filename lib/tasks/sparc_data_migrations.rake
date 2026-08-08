# v1.8.3 — operator-facing entry points for deferred data migrations.
# Normal boot path: the after_initialize hook in
# `config/initializers/enqueue_data_migrations.rb` enqueues
# `DeferredDataMigrationJob`, which calls the runner. These rake
# tasks let operators trigger / inspect manually from a one-off
# ECS task or a Rails console.
namespace :sparc do
  namespace :data_migrations do
    desc "Run all pending deferred data migrations now (synchronous; for operator use)"
    task run: :environment do
      result = DeferredDataMigrationRunner.run_all_pending

      unless result
        puts "[sparc:data_migrations:run] another container holds the advisory lock; nothing to do here"
        next
      end

      # Report the OUTCOME, not merely that the runner returned.
      #
      # This previously printed "complete" whenever `run_all_pending` returned
      # truthy — which it does even when every migration failed. An operator
      # running this to repair a failed migration was told it had worked while
      # the row stayed `failed` with 0 records processed. A repair tool that
      # cannot report its own failure is worse than no repair tool.
      failed = DataMigrationRun.where(status: "failed").order(:created_at)
      if failed.any?
        warn "[sparc:data_migrations:run] FAILED (#{failed.count}):"
        failed.each { |r| warn "  #{r.name}: #{r.error_message}" }
        abort "[sparc:data_migrations:run] one or more data migrations failed"
      end

      puts "[sparc:data_migrations:run] complete — " \
           "#{DataMigrationRun.where(status: 'completed').count} completed, " \
           "#{DataMigrationRun.where(status: 'pending').count} still pending"
    end

    desc "List the current status of every tracked deferred data migration"
    task status: :environment do
      runs = DataMigrationRun.order(:created_at).to_a
      if runs.empty?
        puts "(no DataMigrationRun rows; nothing to report)"
        next
      end
      width = runs.map { |r| r.name.length }.max
      puts sprintf("%-#{width}s  %-10s  %-25s  %s", "NAME", "STATUS", "COMPLETED_AT", "ERROR")
      runs.each do |r|
        puts sprintf("%-#{width}s  %-10s  %-25s  %s",
                     r.name, r.status, r.completed_at&.iso8601 || "-",
                     r.error_message.to_s.lines.first.to_s.strip.truncate(120))
      end
    end

    desc "Reset a single failed/stuck deferred migration back to pending (NAME=ClassName)"
    task reset: :environment do
      name = ENV["NAME"]
      abort "Usage: NAME=PromoteFoo bin/rake sparc:data_migrations:reset" if name.to_s.strip.empty?

      run = DataMigrationRun.find_by(name: name)
      abort "No DataMigrationRun row for #{name.inspect}" unless run

      run.update!(status: "pending", started_at: nil, completed_at: nil,
                  error_message: "Manually reset by operator at #{Time.current.iso8601}")
      puts "[sparc:data_migrations:reset] #{name} → pending"
    end
  end
end
