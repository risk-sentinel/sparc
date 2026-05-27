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
      if result
        puts "[sparc:data_migrations:run] complete"
      else
        puts "[sparc:data_migrations:run] another container holds the advisory lock; nothing to do here"
      end
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
