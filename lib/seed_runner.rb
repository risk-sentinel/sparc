# SeedRunner — resilient, version-tracked seed orchestration.
#
# Wraps each seed section in error isolation so one failure does not stop
# the entire seed process. Tracks completion via the seed_sections table
# and skips already-completed sections at the current version.
#
# Bump a version in CURRENT_VERSIONS to force a section to re-run on the
# next deployment (passive catch-up for existing databases).
#
# NIST SA-10: Developer Configuration Management
module SeedRunner
  CURRENT_VERSIONS = {
    "nist_rev5_catalog"    => "2.0.0",
    "nist_rev4_catalog"    => "2.0.0",
    "roles"                => "1.0.0",
    "admin_user"           => "1.1.0",
    "fedramp_20x_ksi"      => "1.0.0",
    "converters"           => "1.2.0",
    "demo_organization"    => "1.0.0",
    "demo_auth_boundary"   => "1.0.0",
    "demo_ssp_sar"         => "1.0.0",
    "demo_catalog_guidance" => "1.0.0",
    "demo_evidence"        => "1.0.0",
    "demo_sample_artifacts" => "1.0.0"
  }.freeze

  # Ensure the seed_sections table exists (handles first-ever run before migrations).
  def self.ensure_tracking_table!
    return if ActiveRecord::Base.connection.table_exists?(:seed_sections)

    puts "[SeedRunner] Creating seed_sections tracking table..."
    ActiveRecord::Base.connection.create_table :seed_sections do |t|
      t.string :name, null: false
      t.string :version, default: "1.0.0"
      t.string :status, default: "pending"
      t.text :error_message
      t.integer :records_created, default: 0
      t.datetime :completed_at
      t.timestamps
    end
    ActiveRecord::Base.connection.add_index :seed_sections, :name, unique: true
  end

  # Run a named seed section with error isolation and version tracking.
  #
  #   SeedRunner.run_section("nist_rev5_catalog") do
  #     # ... seed logic ...
  #   end
  #
  # Skips if already completed at the current version.
  # On error: logs the failure but does NOT re-raise — seeding continues.
  def self.run_section(name, version: nil, &block)
    ensure_tracking_table!
    version ||= CURRENT_VERSIONS[name] || "1.0.0"

    record = SeedSection.find_or_initialize_by(name: name)

    # Skip if already completed at current version
    if record.persisted? && record.status == "completed" && record.version == version
      puts "[SeedRunner] ✓ #{name} v#{version} — already completed, skipping."
      return
    end

    puts "[SeedRunner] Running: #{name} v#{version}..."
    record.update!(status: "pending", version: version, error_message: nil, records_created: 0)

    begin
      block.call
      record.update!(status: "completed", completed_at: Time.current)
      puts "[SeedRunner] ✓ #{name} v#{version} — completed."
    rescue => e
      error_detail = "#{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}"
      record.update!(status: "failed", error_message: error_detail)

      puts ""
      puts "[SeedRunner] ✗ ERROR in #{name}: #{e.class} — #{e.message}"
      puts "[SeedRunner]   Seed will continue. This section can be retried by re-running db:seed."
      puts "[SeedRunner]   To report this issue, include the error above and your SPARC version."
      puts ""

      Rails.logger.error("[SeedRunner] #{name} v#{version} failed: #{error_detail}")
    end
  end

  # Print a summary table of all seed sections.
  def self.summary
    ensure_tracking_table!

    puts ""
    puts "=" * 70
    puts "  SEED COMPLETENESS REPORT"
    puts "=" * 70

    SeedSection.order(:name).each do |s|
      icon = case s.status
      when "completed" then "✓ OK  "
      when "failed"    then "✗ FAIL"
      when "skipped"   then "- SKIP"
      else                  "? PEND"
      end
      puts "  [#{icon}] #{s.name} v#{s.version}"
      if s.error_message.present?
        puts "           Error: #{s.error_message.lines.first&.strip}"
      end
    end

    failed = SeedSection.where(status: "failed")
    if failed.any?
      puts ""
      puts "  ⚠ WARNING: #{failed.count} seed section(s) failed."
      puts "  The application will function, but some reference data may be missing."
      puts "  Re-run: bundle exec rails db:seed"
      puts "  To report: include the errors above and your SPARC version."
    else
      puts ""
      puts "  All seed sections completed successfully."
    end
    puts "=" * 70
    puts ""
  end

  # Verify expected data exists and log a completeness report.
  # Never raises — only reports.
  def self.verify_completeness
    ensure_tracking_table!

    checks = {
      "NIST SP 800-53 Rev 5 catalog" => -> { ControlCatalog.exists?(name: "NIST SP 800-53 Revision 5") || ControlCatalog.where("name LIKE ?", "%Rev 5%").exists? },
      "NIST SP 800-53 Rev 4 catalog" => -> { ControlCatalog.where("name LIKE ?", "%Rev%4%").exists? || ControlCatalog.where("name LIKE ?", "%Revision 4%").exists? },
      "Converter: DISA CCI"          => -> { Converter.exists?(converter_type: "cci_to_nist") },
      "Converter: CIS Controls"      => -> { Converter.exists?(converter_type: "cis_to_nist") },
      "Converter: SCAP/OVAL"         => -> { Converter.exists?(converter_type: "scap_oval_to_nist") },
      "FedRAMP 20x KSI catalog"      => -> { ControlCatalog.exists?(source: "FedRAMP 20x") },
      "Roles"                        => -> { Role.any? },
      "Admin user"                   => -> { User.exists?(admin: true) }
    }

    # Sample files on disk
    sample_files = %w[
      samples/nist-traditional-demo/ssp-acme-cloud.json
      samples/nist-traditional-demo/sar-acme-cloud.json
      samples/nist-traditional-demo/sap-acme-cloud.json
      samples/nist-traditional-demo/poam-acme-cloud.json
      samples/nist-traditional-demo/cdef-web-server.json
      samples/fedramp-20x-demo/ksi-compliance-report.json
      samples/fedramp-20x-demo/ksi-compliance-report.yaml
      samples/fedramp-20x-demo/ksi-validation-evidence.json
    ]

    puts ""
    puts "-" * 70
    puts "  DATA COMPLETENESS CHECK"
    puts "-" * 70

    missing = []
    checks.each do |label, check|
      begin
        present = check.call
        icon = present ? "✓" : "✗"
        puts "  [#{icon}] #{label}"
        missing << label unless present
      rescue => e
        puts "  [?] #{label} — check failed: #{e.message}"
        missing << label
      end
    end

    puts ""
    puts "  Sample files on disk:"
    sample_files.each do |path|
      full_path = Rails.root.join(path)
      icon = File.exist?(full_path) ? "✓" : "✗"
      puts "  [#{icon}] #{path}"
      missing << path unless File.exist?(full_path)
    end

    if missing.any?
      puts ""
      puts "  ⚠ #{missing.count} item(s) missing. Re-run: bundle exec rails db:seed"
    else
      puts ""
      puts "  All required data present."
    end
    puts "-" * 70
    puts ""
  end
end
