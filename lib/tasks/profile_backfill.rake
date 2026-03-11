namespace :profile do
  desc "Normalize profile control IDs to OSCAL canonical format (ac-1) and backfill titles"
  task normalize_control_ids: :environment do
    total_profiles = 0
    total_normalized = 0

    ProfileDocument.find_each do |profile|
      profile.profile_controls.find_each do |pc|
        raw = pc.control_id.to_s
        # Convert any format (AC-01, AC-1, ac-1) to canonical OSCAL: ac-1
        normalized = raw.strip.downcase
                        .gsub(/\s+/, "-")
                        .gsub("(", ".").gsub(")", "")
                        .sub(/\A([a-z]+-?)0+(\d)/) { "#{$1}#{$2}" }
        next if raw == normalized

        pc.update_column(:control_id, normalized)
        total_normalized += 1
      end
      total_profiles += 1
    end

    puts "Done. Scanned #{total_profiles} profile(s), normalized #{total_normalized} control ID(s)."

    # Also backfill titles from linked catalogs
    ProfileDocument.where.not(control_catalog_id: nil).find_each do |profile|
      title_map = profile.control_catalog.catalog_controls.pluck(:control_id, :title).to_h
      updated = 0
      profile.profile_controls.where(title: nil).find_each do |pc|
        mapped = title_map[pc.control_id]
        if mapped.present?
          pc.update_column(:title, mapped)
          updated += 1
        end
      end
      puts "  '#{profile.name}': enriched #{updated} title(s)" if updated.positive?
    end
  end

  desc "Backfill control_catalog_id and control titles on existing profile documents"
  task backfill_catalog: :environment do
    # Step 1: Ensure catalogs have their OSCAL UUIDs stored
    backfill_catalog_uuids

    catalogs = ControlCatalog.all.to_a
    if catalogs.empty?
      puts "No catalogs found. Import a catalog first."
      next
    end

    profiles = ProfileDocument.where(control_catalog_id: nil)
    total = profiles.count
    if total.zero?
      puts "All profiles are already linked to a catalog. Nothing to do."
      next
    end

    puts "Found #{total} profile(s) without a linked catalog."
    puts "Available catalogs: #{catalogs.map { |c| "#{c.id}: #{c.name}" }.join(', ')}"
    puts "=" * 60

    linked = 0
    enriched = 0

    profiles.find_each do |profile|
      catalog_ref = profile.import_metadata&.dig("catalog_href")
      back_matter = profile.import_metadata&.dig("back_matter") || []

      matched_catalog = find_matching_catalog(catalog_ref, back_matter, catalogs)
      next unless matched_catalog

      profile.update_column(:control_catalog_id, matched_catalog.id)
      linked += 1
      puts "  Linked '#{profile.name}' → '#{matched_catalog.name}'"

      # Enrich control titles from the matched catalog
      title_map = matched_catalog.catalog_controls.pluck(:control_id, :title).to_h
      updated_titles = 0
      profile.profile_controls.where(title: nil).find_each do |pc|
        mapped_title = title_map[pc.control_id]
        if mapped_title.present?
          pc.update_column(:title, mapped_title)
          updated_titles += 1
        end
      end

      if updated_titles.positive?
        enriched += updated_titles
        puts "    Enriched #{updated_titles} control title(s)"
      end
    end

    puts "=" * 60
    puts "Done. Linked #{linked}/#{total} profile(s). Enriched #{enriched} control title(s)."
  end
end

# ── Catalog UUID backfill ────────────────────────────────────────────────

# Populate metadata_extra["catalog_uuid"] on existing catalogs by reading
# the OSCAL JSON fixtures. Catalogs imported before the auto-linking code
# won't have this field set; this fills it in for matching.
def backfill_catalog_uuids
  oscal_sources = {
    "NIST SP 800-53 Rev 4" => Rails.root.join("spec/fixtures/files/catalogs/NIST_SP-800-53_rev4_catalog.json")
  }

  updated = 0
  oscal_sources.each do |catalog_name, path|
    catalog = ControlCatalog.find_by(name: catalog_name)
    next unless catalog
    next if catalog.metadata_extra&.dig("catalog_uuid").present?
    next unless File.exist?(path)

    data = JSON.parse(File.read(path))
    uuid = data.dig("catalog", "uuid")
    next unless uuid.present?

    extra = (catalog.metadata_extra || {}).merge("catalog_uuid" => uuid)
    catalog.update_column(:metadata_extra, extra)
    updated += 1
    puts "  Backfilled catalog_uuid on '#{catalog_name}': #{uuid}"
  end

  puts "  Catalog UUID backfill: #{updated} catalog(s) updated." if updated.positive?
end

# ── Matching helpers (same logic as ProfileJsonParserService) ─────────────

def find_matching_catalog(catalog_ref, back_matter, catalogs)
  # Strategy 1: Direct UUID match
  if catalog_ref.present?
    ref_uuid = catalog_ref.delete_prefix("#")
    match = catalogs.find { |c| c.metadata_extra&.dig("catalog_uuid") == ref_uuid }
    return match if match
  end

  # Strategy 2: Resolve back-matter resource and match rlinks against catalog names
  if catalog_ref&.start_with?("#") && back_matter.any?
    resource_uuid = catalog_ref.delete_prefix("#")
    resource = back_matter.find { |r| r["uuid"] == resource_uuid }

    if resource
      rlinks = resource["rlinks"] || []
      rlink_hrefs = rlinks.map { |rl| rl["href"].to_s.downcase }

      catalogs.each do |catalog|
        return catalog if rlinks_match_catalog?(rlink_hrefs, catalog)
      end
    end
  end

  nil
end

def rlinks_match_catalog?(rlink_hrefs, catalog)
  catalog_name = catalog.name.downcase

  rlink_hrefs.any? do |href|
    rlink_rev = href[/rev\.?\s*(\d+)/i, 1] || href[/revision[_\s]*(\d+)/i, 1]
    catalog_rev = catalog_name[/rev\.?\s*(\d+)/i, 1] || catalog_name[/revision[_\s]*(\d+)/i, 1]

    href.include?("800-53") && catalog_name.include?("800-53") &&
      rlink_rev.present? && catalog_rev.present? &&
      rlink_rev == catalog_rev
  end
end
