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

      puts "Re-importing '#{catalog_name}' (id=#{catalog.id}) from #{File.basename(fixture_path)}..."
      old_count = catalog.catalog_controls.count

      # Delete existing catalog controls (cascade through families)
      catalog.control_families.each do |family|
        family.catalog_controls.delete_all
      end
      catalog.control_families.delete_all

      puts "  Cleared #{old_count} old control(s) and associated families."

      # Re-import using the updated CatalogImportService, passing the existing
      # catalog so that controls are imported into the SAME catalog (not a new
      # one named after the OSCAL metadata title).
      file_io = File.open(fixture_path)
      result = CatalogImportService.call(file_io, File.basename(fixture_path), existing_catalog: catalog)
      file_io.close

      # Count top-level controls vs sub-parts for clarity
      all_count = result[:catalog].catalog_controls.count
      top_level_count = result[:catalog].catalog_controls.where("control_id ~ ?", '^[a-z]+-[0-9]+(\\.[0-9]+)?$').count
      sub_part_count = all_count - top_level_count
      puts "  Imported: #{result[:families]} families, #{all_count} total records (#{top_level_count} controls + #{sub_part_count} sub-parts)"
      puts "  Controls now include enhancements, label, and sort_id columns."

      # Clean up any duplicate catalog that was created by a previous (buggy)
      # run where CatalogImportService used the OSCAL metadata title instead
      # of the existing catalog name.
      oscal_title = JSON.parse(File.read(fixture_path)).dig("catalog", "metadata", "title")
      if oscal_title.present? && oscal_title != catalog_name
        dupe = ControlCatalog.find_by(name: oscal_title)
        if dupe
          dupe_controls = dupe.catalog_controls.count
          dupe.control_families.each { |f| f.catalog_controls.delete_all }
          dupe.control_families.delete_all
          dupe.destroy!
          puts "  🧹 Cleaned up duplicate catalog '#{oscal_title}' (had #{dupe_controls} controls)"
        end
      end
    end

    # Normalize existing profile control IDs to OSCAL canonical format
    puts "\n" + "=" * 60
    puts "Normalizing existing profile control IDs to OSCAL canonical format..."

    total_normalized = 0
    ProfileDocument.find_each do |profile|
      profile.profile_controls.find_each do |pc|
        raw = pc.control_id.to_s
        # Convert uppercase padded IDs to OSCAL canonical format:
        #   "AC-01"    → "ac-1"
        #   "AC-02(1)" → "ac-2.1"
        #   "AC-02.01" → "ac-2.1"
        normalized = raw.strip.downcase
                        .gsub(/\s+/, "-")
                        .gsub("(", ".").gsub(")", "")
                        .gsub(/(?<=-|\.)0+(\d)/) { $1 }
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
    puts "Top-level controls (base + enhancements) are selectable on the Manage Controls page."
    puts "Sub-parts (statement fragments like ac-1a) are stored but not shown as selectable."
  end
end
