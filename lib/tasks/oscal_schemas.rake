namespace :oscal do
  desc "Seed OSCAL JSON schemas from NIST GitHub (with disk fallback)"
  task seed_schemas: :environment do
    require "net/http"
    require "digest"

    # Disk fallback directory (existing schemas shipped with SPARC)
    disk_dir = Rails.root.join("lib", "oscal_schemas")

    # Legacy filename mapping — disk files use slightly different names than NIST
    legacy_file_map = {
      "oscal_component-definition_schema.json" => "oscal_component_schema.json",
      "oscal_assessment-results_schema.json"   => "oscal_assessment-results_schema.json",
      "oscal_assessment-plan_schema.json"      => "oscal_assessment-plan_schema.json"
    }

    stats = { downloaded: 0, disk_fallback: 0, skipped: 0, errors: 0 }

    OscalSchema::SUPPORTED_VERSIONS.each do |version|
      OscalSchema::DOCUMENT_TYPE_MAP.each do |doc_type, config|
        # Mapping schemas only exist in 1.2.0+
        if doc_type == "mapping" && !OscalSchema::MAPPING_VERSIONS.include?(version)
          stats[:skipped] += 1
          next
        end

        label = "#{doc_type} v#{version}"
        raw_json = nil
        source_url = OscalSchema.nist_url(version, doc_type)

        # Attempt NIST download
        begin
          uri = URI(source_url)
          response = Net::HTTP.get_response(uri)
          if response.is_a?(Net::HTTPSuccess)
            raw_json = JSON.parse(response.body)
            puts "  ✓ Downloaded #{label}"
            stats[:downloaded] += 1
          else
            puts "  ✗ HTTP #{response.code} for #{label} — trying disk fallback"
          end
        rescue StandardError => e
          puts "  ✗ Download failed for #{label}: #{e.message} — trying disk fallback"
        end

        # Disk fallback for the version that ships with SPARC
        if raw_json.nil?
          disk_name = legacy_file_map[config[:file]] || config[:file]
          disk_path = disk_dir.join(disk_name)
          if File.exist?(disk_path)
            raw_json = JSON.parse(File.read(disk_path))
            source_url = "file://#{disk_path}"
            puts "  ↩ Disk fallback for #{label}: #{disk_name}"
            stats[:disk_fallback] += 1
          else
            puts "  ✗ No disk fallback for #{label} — skipping"
            stats[:errors] += 1
            next
          end
        end

        # Compute checksum and preprocess
        checksum = Digest::SHA256.hexdigest(raw_json.to_json)
        preprocessed = OscalSchema.preprocess_schema(raw_json)

        # Upsert
        schema = OscalSchema.find_or_initialize_by(
          oscal_version: version,
          document_type: doc_type,
          schema_format: "json"
        )
        schema.assign_attributes(
          raw_schema:          raw_json,
          preprocessed_schema: preprocessed,
          root_key:            config[:root_key],
          source_url:          source_url,
          checksum:            checksum,
          active:              true
        )
        schema.save!
      end
    end

    total = OscalSchema.count
    puts ""
    puts "OSCAL schema seed complete:"
    puts "  Downloaded:    #{stats[:downloaded]}"
    puts "  Disk fallback: #{stats[:disk_fallback]}"
    puts "  Skipped:       #{stats[:skipped]}"
    puts "  Errors:        #{stats[:errors]}"
    puts "  Total in DB:   #{total}"
  end
end
