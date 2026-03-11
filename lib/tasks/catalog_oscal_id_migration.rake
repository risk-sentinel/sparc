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
          # Re-link any profiles that were pointing at the duplicate catalog
          relinked = ProfileDocument.where(control_catalog_id: dupe.id).update_all(control_catalog_id: catalog.id)
          puts "  🔗 Re-linked #{relinked} profile(s) from duplicate catalog (id=#{dupe.id}) → canonical catalog (id=#{catalog.id})" if relinked.positive?

          dupe_controls = dupe.catalog_controls.count
          dupe.control_families.each { |f| f.catalog_controls.delete_all }
          dupe.control_families.delete_all
          dupe.destroy!
          puts "  🧹 Cleaned up duplicate catalog '#{oscal_title}' (id=#{dupe.id}, had #{dupe_controls} controls)"
        end
      end
    end

    # Also link any unlinked profiles that reference Rev 4 via their import metadata
    puts "\nChecking for unlinked profiles..."
    unlinked_profiles = ProfileDocument.where(control_catalog_id: nil)
    if unlinked_profiles.any?
      rev4_catalog = ControlCatalog.find_by(name: "NIST SP 800-53 Rev 4")
      if rev4_catalog
        unlinked_profiles.find_each do |profile|
          catalog_ref = profile.import_metadata&.dig("catalog_href")
          back_matter = profile.import_metadata&.dig("back_matter") || []
          # Check if this profile references 800-53 Rev 4
          rlink_hrefs = back_matter.flat_map { |r| (r["rlinks"] || []).map { |rl| rl["href"].to_s } }
          refs = [ catalog_ref.to_s, *rlink_hrefs ]
          if refs.any? { |r| r.include?("800-53") && (r.include?("rev4") || r.include?("rev-4") || r.include?("revision-4")) }
            profile.update_column(:control_catalog_id, rev4_catalog.id)
            puts "  🔗 Linked '#{profile.name}' → '#{rev4_catalog.name}' (id=#{rev4_catalog.id})"
          end
        end
      end
    end

    # Normalize existing profile control IDs to OSCAL canonical format
    puts "\n" + "=" * 60
    puts "Normalizing existing profile control IDs to OSCAL canonical format..."

    total_normalized = 0
    ProfileDocument.find_each do |profile|
      profile_normalized = 0
      profile.profile_controls.find_each do |pc|
        raw = pc.control_id.to_s
        # Convert uppercase padded IDs to OSCAL canonical format:
        #   "AC-01"    → "ac-1"       "AC-01A"   → "ac-1a"
        #   "AC-02(1)" → "ac-2.1"     "AC-01A.1" → "ac-1a.1"
        normalized = raw.strip.downcase
                        .gsub(/\s+/, "-")
                        .gsub("(", ".").gsub(")", "")
                        .gsub(/(?<=-|\.)0+(\d)/) { $1 }
        next if raw == normalized

        pc.update_column(:control_id, normalized)
        total_normalized += 1
        profile_normalized += 1
      end
      puts "  '#{profile.name}': normalized #{profile_normalized} control ID(s)" if profile_normalized.positive?
    end
    puts "  Normalized #{total_normalized} total profile control ID(s)."

    # Re-enrich titles from newly linked catalogs
    puts "\nRe-enriching profile control titles from catalogs..."
    total_enriched = 0
    ProfileDocument.where.not(control_catalog_id: nil).find_each do |profile|
      title_map = profile.control_catalog.catalog_controls.pluck(:control_id, :title).to_h
      profile_enriched = 0
      profile.profile_controls.find_each do |pc|
        mapped = title_map[pc.control_id]
        if mapped.present? && pc.title != mapped
          pc.update_column(:title, mapped)
          total_enriched += 1
          profile_enriched += 1
        end
      end
      puts "  '#{profile.name}': enriched #{profile_enriched} title(s)" if profile_enriched.positive?
    end
    puts "  Enriched #{total_enriched} total profile control title(s)."

    # Print summary
    puts "\n" + "=" * 60
    puts "Done. Summary:"
    ControlCatalog.all.each do |cat|
      puts "  Catalog '#{cat.name}' (id=#{cat.id}): #{cat.catalog_controls.count} controls"
    end
    ProfileDocument.where.not(control_catalog_id: nil).each do |prof|
      profile_ids = prof.profile_controls.pluck(:control_id).to_set
      catalog_ids = prof.control_catalog.catalog_controls.pluck(:control_id).to_set
      matched = (profile_ids & catalog_ids).size
      puts "  Profile '#{prof.name}' → catalog_id=#{prof.control_catalog_id}: #{matched}/#{profile_ids.size} controls matched"
    end
  end
end
