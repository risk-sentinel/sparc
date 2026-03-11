namespace :catalog do
  desc "Re-import OSCAL catalogs with canonical IDs (ac-1 format) and normalize existing profile controls"
  task reimport_oscal: :environment do
    # Map each OSCAL fixture by its document UUID (from catalog.uuid in the JSON).
    # UUID is the OSCAL-standard identifier — names can vary between environments.
    oscal_fixtures = [
      {
        uuid: "b954d3b7-d2c7-453b-8eb2-459e8d3b8462",
        fallback_name: "NIST SP 800-53 Rev 4",
        path: Rails.root.join("spec/fixtures/files/catalogs/NIST_SP-800-53_rev4_catalog.json")
      }
    ]

    oscal_fixtures.each do |fixture|
      unless File.exist?(fixture[:path])
        puts "  ⚠ Fixture not found: #{fixture[:path]} — skipping"
        next
      end

      # Find catalog by UUID first (stored in metadata_extra), then fall back to name
      catalog = ControlCatalog.find_by("metadata_extra->>'catalog_uuid' = ?", fixture[:uuid])
      catalog ||= ControlCatalog.find_by(name: fixture[:fallback_name])

      unless catalog
        puts "  ⚠ No catalog found for UUID #{fixture[:uuid]} or name '#{fixture[:fallback_name]}' — skipping"
        next
      end

      puts "Re-importing catalog (id=#{catalog.id}, name='#{catalog.name}') from #{File.basename(fixture[:path])}..."
      old_count = catalog.catalog_controls.count

      # Delete existing catalog controls (cascade through families)
      catalog.control_families.each do |family|
        family.catalog_controls.delete_all
      end
      catalog.control_families.delete_all

      puts "  Cleared #{old_count} old control(s) and associated families."

      # Re-import using the updated CatalogImportService, passing the existing
      # catalog so controls are imported into the SAME record.
      file_io = File.open(fixture[:path])
      result = CatalogImportService.call(file_io, File.basename(fixture[:path]), existing_catalog: catalog)
      file_io.close

      # Count top-level controls vs sub-parts for clarity
      all_count = result[:catalog].catalog_controls.count
      top_level_count = result[:catalog].catalog_controls.where("control_id ~ ?", '^[a-z]+-[0-9]+(\\.[0-9]+)?$').count
      sub_part_count = all_count - top_level_count
      puts "  Imported: #{result[:families]} families, #{all_count} total records (#{top_level_count} controls + #{sub_part_count} sub-parts)"

      # Clean up any duplicate catalog created by a previous run (matched by
      # the OSCAL metadata title which differs from the seeded catalog name).
      oscal_data = JSON.parse(File.read(fixture[:path]))
      oscal_title = oscal_data.dig("catalog", "metadata", "title")
      oscal_uuid  = oscal_data.dig("catalog", "uuid")

      # Find duplicates: any OTHER catalog with same UUID or same OSCAL title
      ControlCatalog.where.not(id: catalog.id).find_each do |other|
        other_uuid = other.metadata_extra&.dig("catalog_uuid")
        is_dupe = (other_uuid.present? && other_uuid == oscal_uuid) ||
                  (oscal_title.present? && other.name == oscal_title)
        next unless is_dupe

        # Re-link profiles before destroying the duplicate
        relinked = ProfileDocument.where(control_catalog_id: other.id).update_all(control_catalog_id: catalog.id)
        puts "  🔗 Re-linked #{relinked} profile(s) from duplicate (id=#{other.id}) → canonical (id=#{catalog.id})" if relinked.positive?

        dupe_controls = other.catalog_controls.count
        other.control_families.each { |f| f.catalog_controls.delete_all }
        other.control_families.delete_all
        other.destroy!
        puts "  🧹 Cleaned up duplicate catalog '#{other.name}' (id=#{other.id}, had #{dupe_controls} controls)"
      end
    end

    # Link unlinked profiles by matching their import_metadata catalog UUID
    puts "\nChecking for unlinked profiles..."
    unlinked_profiles = ProfileDocument.where(control_catalog_id: nil)
    if unlinked_profiles.any?
      catalogs = ControlCatalog.all.to_a
      unlinked_profiles.find_each do |profile|
        catalog_ref = profile.import_metadata&.dig("catalog_href")
        next if catalog_ref.blank?

        # Strategy 1: Direct UUID match (catalog_ref = "#<uuid>")
        ref_uuid = catalog_ref.delete_prefix("#")
        match = catalogs.find { |c| c.metadata_extra&.dig("catalog_uuid") == ref_uuid }

        # Strategy 2: Resolve back-matter rlinks for revision matching
        unless match
          back_matter = profile.import_metadata&.dig("back_matter") || []
          resource = back_matter.find { |r| r["uuid"] == ref_uuid }
          if resource
            rlink_hrefs = (resource["rlinks"] || []).map { |rl| rl["href"].to_s.downcase }
            match = catalogs.find do |c|
              cat_name = c.name.downcase
              rlink_hrefs.any? do |href|
                rlink_rev = href[/rev\.?\s*(\d+)/i, 1] || href[/revision[_\s]*(\d+)/i, 1]
                catalog_rev = cat_name[/rev\.?\s*(\d+)/i, 1] || cat_name[/revision[_\s]*(\d+)/i, 1]
                href.include?("800-53") && cat_name.include?("800-53") &&
                  rlink_rev.present? && catalog_rev.present? &&
                  rlink_rev == catalog_rev
              end
            end
          end
        end

        if match
          profile.update_column(:control_catalog_id, match.id)
          puts "  🔗 Linked '#{profile.name}' → '#{match.name}' (id=#{match.id})"
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
      uuid = cat.metadata_extra&.dig("catalog_uuid")
      puts "  Catalog '#{cat.name}' (id=#{cat.id}, uuid=#{uuid || 'none'}): #{cat.catalog_controls.count} controls"
    end
    ProfileDocument.where.not(control_catalog_id: nil).each do |prof|
      profile_ids = prof.profile_controls.pluck(:control_id).to_set
      catalog_ids = prof.control_catalog.catalog_controls.pluck(:control_id).to_set
      matched = (profile_ids & catalog_ids).size
      puts "  Profile '#{prof.name}' → catalog_id=#{prof.control_catalog_id}: #{matched}/#{profile_ids.size} matched"
    end
  end
end
