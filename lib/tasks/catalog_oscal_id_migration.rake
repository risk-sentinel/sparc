namespace :catalog do
  desc "Re-import OSCAL catalogs with canonical IDs (ac-1 format) and normalize existing profile controls"
  task reimport_oscal: :environment do
    oscal_fixtures = {
      "NIST SP 800-53 Rev 4" => Rails.root.join("spec/fixtures/files/catalogs/NIST_SP-800-53_rev4_catalog.json")
    }

    oscal_fixtures.each do |catalog_name, fixture_path|
      unless File.exist?(fixture_path)
        puts "  ⚠ Fixture not found: #{fixture_path} — skipping #{catalog_name}"
        next
      end

      catalog = ControlCatalog.find_by(name: catalog_name)
      unless catalog
        puts "  ⚠ Catalog '#{catalog_name}' not found in database — skipping"
        next
      end

      puts "Re-importing '#{catalog_name}' from #{File.basename(fixture_path)}..."
      old_count = catalog.catalog_controls.count

      # Delete existing catalog controls (cascade through families)
      catalog.control_families.each do |family|
        family.catalog_controls.delete_all
      end
      catalog.control_families.delete_all

      puts "  Cleared #{old_count} old control(s) and associated families."

      # Re-import using the updated CatalogImportService
      file_io = File.open(fixture_path)
      result = CatalogImportService.call(file_io, File.basename(fixture_path))
      file_io.close

      new_count = result[:catalog].catalog_controls.count
      puts "  Imported: #{result[:families]} families, #{new_count} controls (#{result[:created]} new, #{result[:updated]} updated)"
      puts "  Controls now include enhancements, label, and sort_id columns."
    end

    # Normalize existing profile control IDs to OSCAL canonical format
    puts "\n" + "=" * 60
    puts "Normalizing existing profile control IDs to OSCAL canonical format..."

    total_normalized = 0
    ProfileDocument.find_each do |profile|
      profile.profile_controls.find_each do |pc|
        raw = pc.control_id.to_s
        normalized = raw.strip.downcase
                        .gsub(/\s+/, "-")
                        .gsub("(", ".").gsub(")", "")
                        .sub(/\A([a-z]+-?)0+(\d)/) { "#{$1}#{$2}" }
        next if raw == normalized

        pc.update_column(:control_id, normalized)
        total_normalized += 1
      end
    end
    puts "  Normalized #{total_normalized} profile control ID(s)."

    # Re-enrich titles from newly linked catalogs
    puts "\nRe-enriching profile control titles from catalogs..."
    total_enriched = 0
    ProfileDocument.where.not(control_catalog_id: nil).find_each do |profile|
      title_map = profile.control_catalog.catalog_controls.pluck(:control_id, :title).to_h
      profile.profile_controls.find_each do |pc|
        mapped = title_map[pc.control_id]
        if mapped.present? && pc.title != mapped
          pc.update_column(:title, mapped)
          total_enriched += 1
        end
      end
    end
    puts "  Enriched #{total_enriched} profile control title(s)."

    puts "\n" + "=" * 60
    puts "Done. Catalogs now use OSCAL canonical IDs (ac-1, ac-2.1) with label/sort_id columns."
  end
end
