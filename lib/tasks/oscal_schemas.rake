namespace :oscal do
  # GitHub release-asset URLs respond with HTTP 302 redirects to a
  # signed AWS S3 download URL. Net::HTTP.get_response doesn't follow
  # redirects, so wrap it. Aborts after MAX_REDIRECTS to prevent loops.
  MAX_REDIRECTS = 5

  # Diagnostic output for the bundle/seed tasks, routed through an overridable
  # IO. The failure-path specs deliberately exercise the error branches
  # (checksum mismatch, missing file, no-network), and the task's own ✗/FAILED
  # logging used to flood the test log — indistinguishable from a real failure
  # (#747). Specs set Thread.current[:oscal_task_io] to capture it; real
  # `bin/rails oscal:*` runs keep writing to $stdout unchanged.
  def oscal_out
    Thread.current[:oscal_task_io] || $stdout
  end

  def oscal_log(message = "")
    oscal_out.puts(message)
  end

  def fetch_following_redirects(url, depth = 0)
    raise "redirect loop (>#{MAX_REDIRECTS}) for #{url}" if depth > MAX_REDIRECTS

    uri = URI(url)
    response = SparcHttp.start(uri) do |http|  # proxy-aware (#775)
      http.request(Net::HTTP::Get.new(uri.request_uri))
    end

    case response
    when Net::HTTPSuccess
      response.body
    when Net::HTTPRedirection
      fetch_following_redirects(response["location"], depth + 1)
    else
      raise "HTTP #{response.code} from #{url}"
    end
  end

  # Build-time task that downloads every supported (version × doc_type)
  # OSCAL schema combination from NIST GitHub and writes it to
  # `lib/oscal_schemas_bundle/v<version>/<file>` along with a
  # manifest.json carrying SHA-256 checksums.
  #
  # The Dockerfile build stage runs this so the production image ships
  # with all five OSCAL schemas already present — `oscal:seed_schemas`
  # at deploy time loads from the bundle (no NIST GitHub fetch). See #453.
  desc "Bundle OSCAL JSON schemas to lib/oscal_schemas_bundle/ for offline-friendly seeding (#453)"
  task bundle_schemas: :environment do
    require "net/http"
    require "digest"
    require "fileutils"

    bundle_dir = Rails.root.join("lib", "oscal_schemas_bundle")
    FileUtils.mkdir_p(bundle_dir)

    entries  = []
    failures = []

    OscalSchema::SUPPORTED_VERSIONS.each do |version|
      version_dir = bundle_dir.join("v#{version}")
      FileUtils.mkdir_p(version_dir)

      OscalSchema::DOCUMENT_TYPE_MAP.each do |doc_type, config|
        # Mapping schemas only exist in 1.2.0+
        next if doc_type == "mapping" && !OscalSchema::MAPPING_VERSIONS.include?(version)

        label = "#{doc_type} v#{version}"
        url   = OscalSchema.nist_url(version, doc_type)

        body =
          begin
            fetch_following_redirects(url)
          rescue StandardError => e
            failures << "#{label}: #{e.message}"
            oscal_log "  ✗ #{label}: #{e.message}"
            nil
          end

        if body.nil? && !failures.last&.include?(label)
          failures << "#{label}: empty body from #{url}"
          oscal_log "  ✗ #{label}: empty body"
        end

        next if body.nil?

        begin
          JSON.parse(body)
        rescue JSON::ParserError => e
          failures << "#{label}: malformed JSON — #{e.message}"
          oscal_log "  ✗ #{label}: malformed JSON"
          next
        end

        file_path = version_dir.join(config[:file])
        File.write(file_path, body)
        sha256 = Digest::SHA256.hexdigest(body)

        entries << {
          "version"       => version,
          "document_type" => doc_type,
          "file"          => "v#{version}/#{config[:file]}",
          "root_key"      => config[:root_key],
          "sha256"        => sha256,
          "source_url"    => url,
          "size"          => body.bytesize
        }
        oscal_log "  ✓ #{label} → v#{version}/#{config[:file]} (#{body.bytesize} bytes, sha256:#{sha256[0..15]}…)"
      end
    end

    manifest = {
      "generated_at"       => Time.now.utc.iso8601,
      "supported_versions" => OscalSchema::SUPPORTED_VERSIONS,
      "default_version"    => OscalSchema::DEFAULT_VERSION,
      "schemas"            => entries.sort_by { |e| [ e["version"], e["document_type"] ] }
    }

    manifest_path = bundle_dir.join("manifest.json")
    File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")

    oscal_log ""
    oscal_log "Bundle written to lib/oscal_schemas_bundle/"
    oscal_log "  Schemas:  #{entries.size}"
    oscal_log "  Manifest: manifest.json"

    if failures.any?
      oscal_log ""
      # ::error:: is a GitHub Actions annotation; only prefix it when actually
      # running under Actions, so local/rspec runs don't show an alarming
      # literal "::error::" line (#747).
      annotation = ENV["GITHUB_ACTIONS"] ? "::error::" : ""
      oscal_log "#{annotation}OSCAL schema bundle failed (#{failures.size} entries):"
      failures.each { |f| oscal_log "  - #{f}" }
      exit 1
    end

    # #1058 — the XSD set follows the JSON set, always. It was possible to move
    # DEFAULT_VERSION and carry only the JSON half, which is exactly what happened
    # in v1.16.0: XML exports declared 1.2.2 and were validated against 1.2.1 XSDs
    # for an entire release. Invoking it here means the two sets cannot separate
    # again without someone deliberately removing this line.
    Rake::Task["oscal:bundle_xsd_schemas"].invoke
  end

  # #1058 — the XSD set is fetched, not placed by hand.
  #
  # v1.16.0 moved DEFAULT_VERSION to 1.2.2 and `bundle_schemas` carried the JSON
  # set with it. The XSDs did not follow, because nothing fetched them: they had
  # been copied in by hand and no task iterated them. So XML exports declared
  # `oscal-version: 1.2.2` while `validate_xml` checked them against 1.2.1 —
  # "validated" naming a different release from the one the document claims.
  #
  # A hand-maintained set beside an automated one drifts again the next time the
  # version moves, whoever moves it. That was the actual defect; this task is the
  # fix, and `bundle_schemas` invokes it so the two sets cannot separate.
  #
  # Derived from `OscalSchemaValidationService::XSD_SCHEMA_MAP` rather than
  # DOCUMENT_TYPE_MAP: that map is the set the validator actually loads. NIST
  # also publishes an `oscal_mapping_schema.xsd`, but nothing here validates
  # mapping XML, and fetching a file no code reads would be inventory rather than
  # coverage.
  #
  # Single flat directory, not versioned like the JSON bundle: `validate_xml`
  # resolves one file per model with no version in the path, so the set on disk
  # IS the DEFAULT_VERSION set by construction.
  desc "Fetch the OSCAL XSD set for DEFAULT_VERSION into lib/oscal_xsd_schemas/ (#1058)"
  task bundle_xsd_schemas: :environment do
    require "net/http"
    require "digest"
    require "fileutils"

    version = OscalSchema::DEFAULT_VERSION
    xsd_dir = Rails.root.join("lib", "oscal_xsd_schemas")
    FileUtils.mkdir_p(xsd_dir)

    entries  = []
    failures = []

    oscal_log "Fetching OSCAL XSD schemas for v#{version}"

    OscalSchemaValidationService::XSD_SCHEMA_MAP.each do |model, file|
      label = "#{model} v#{version}"
      url   = format(OscalSchema::NIST_SCHEMA_URL_TEMPLATE, version: version, file: file)

      body =
        begin
          fetch_following_redirects(url)
        rescue StandardError => e
          failures << "#{label}: #{e.message}"
          oscal_log "  ✗ #{label}: #{e.message}"
          nil
        end

      if body.nil?
        failures << "#{label}: empty body from #{url}" unless failures.last&.include?(label)
        next
      end

      # A redirect to an HTML error page is still a 200 with a body. An XSD that
      # does not parse must not be written over a working one.
      begin
        Nokogiri::XML(body) { |c| c.strict }
      rescue Nokogiri::XML::SyntaxError => e
        failures << "#{label}: not well-formed XML — #{e.message}"
        oscal_log "  ✗ #{label}: not well-formed XML"
        next
      end

      File.write(xsd_dir.join(file), body)
      sha256 = Digest::SHA256.hexdigest(body)
      entries << {
        "version"    => version,
        "model"      => model.to_s,
        "file"       => file,
        "sha256"     => sha256,
        "source_url" => url,
        "size"       => body.bytesize
      }
      oscal_log "  ✓ #{label} → #{file} (#{body.bytesize} bytes, sha256:#{sha256[0..15]}…)"
    end

    manifest = {
      "generated_at"    => Time.now.utc.iso8601,
      "default_version" => version,
      "schemas"         => entries.sort_by { |e| e["model"] }
    }
    File.write(xsd_dir.join("manifest.json"), JSON.pretty_generate(manifest) + "\n")

    oscal_log ""
    oscal_log "XSD set written to lib/oscal_xsd_schemas/ (#{entries.size} schemas, v#{version})"

    if failures.any?
      annotation = ENV["GITHUB_ACTIONS"] ? "::error::" : ""
      oscal_log "#{annotation}OSCAL XSD fetch failed (#{failures.size} entries):"
      failures.each { |f| oscal_log "  - #{f}" }

      # RAISE, do not `exit`. Rake turns an unhandled exception into a non-zero
      # exit, so the CLI behaviour is identical — but `exit` inside a task that a
      # SPEC invokes terminates the whole rspec process, taking the rest of the
      # suite with it and reporting "0 failures" on the way out.
      #
      # That is not hypothetical: chaining this task into `bundle_schemas` did
      # exactly that. `oscal_schemas_rake_spec` stubs the fetch to return JSON,
      # this task correctly rejected it as not-XML, and the `exit 1` killed the
      # run at whatever point the random order had reached — 6246 examples one
      # run, 3869 the next, always "0 failures".
      raise "OSCAL XSD fetch failed (#{failures.size} entries): #{failures.join('; ')}"
    end
  end

  desc "Seed OSCAL JSON schemas — bundle (offline) → NIST GitHub → disk fallback (#453)"
  task seed_schemas: :environment do
    require "net/http"
    require "digest"

    bundle_dir    = Rails.root.join("lib", "oscal_schemas_bundle")
    manifest_path = bundle_dir.join("manifest.json")

    if manifest_path.exist?
      seed_from_bundle(bundle_dir, manifest_path)
    else
      seed_from_network_with_disk_fallback
    end
  end

  # ── Bundle path (offline) ───────────────────────────────────────────
  #
  # Read each schema file referenced by the manifest, verify its SHA-256
  # against the manifest entry, parse, and upsert into the DB. No
  # network access. Refuses to load a tampered file — failed checksum
  # raises so the operator sees the discrepancy at deploy time.
  def seed_from_bundle(bundle_dir, manifest_path)
    manifest = JSON.parse(File.read(manifest_path))
    stats = { loaded: 0, checksum_failed: 0, skipped: 0, missing: 0 }

    oscal_log "OSCAL schema seed — bundle source (#{manifest_path.to_s.delete_prefix(Rails.root.to_s + '/')})"
    oscal_log "  Generated: #{manifest['generated_at']}"
    oscal_log "  Versions:  #{manifest['supported_versions'].join(', ')}"
    oscal_log ""

    manifest["schemas"].each do |entry|
      label     = "#{entry['document_type']} v#{entry['version']}"
      file_path = bundle_dir.join(entry["file"])

      unless file_path.exist?
        stats[:missing] += 1
        oscal_log "  ✗ #{label}: bundle file missing — #{entry['file']}"
        next
      end

      raw_body = File.read(file_path)
      actual_sha = Digest::SHA256.hexdigest(raw_body)

      if actual_sha != entry["sha256"]
        stats[:checksum_failed] += 1
        oscal_log "  ✗ #{label}: SHA-256 mismatch (manifest=#{entry['sha256'][0..15]}…, actual=#{actual_sha[0..15]}…)"
        next
      end

      raw_json     = JSON.parse(raw_body)
      preprocessed = OscalSchema.preprocess_schema(raw_json)

      schema = OscalSchema.find_or_initialize_by(
        oscal_version: entry["version"],
        document_type: entry["document_type"],
        schema_format: "json"
      )
      schema.assign_attributes(
        raw_schema:          raw_json,
        preprocessed_schema: preprocessed,
        root_key:            entry["root_key"],
        source_url:          "bundle://#{entry['file']}",
        checksum:            actual_sha,
        active:              true
      )
      schema.save!
      stats[:loaded] += 1
      oscal_log "  ✓ #{label} (sha256:#{actual_sha[0..15]}…)"
    end

    oscal_log ""
    oscal_log "OSCAL schema seed complete (bundle):"
    oscal_log "  Loaded:           #{stats[:loaded]}"
    oscal_log "  Checksum failed:  #{stats[:checksum_failed]}"
    oscal_log "  Missing files:    #{stats[:missing]}"
    oscal_log "  Total in DB:      #{OscalSchema.count}"

    if stats[:checksum_failed] > 0 || stats[:missing] > 0
      # Route through oscal_log (not abort, which writes to $stderr regardless)
      # so the failure-path specs capture the message instead of printing it,
      # while still exiting non-zero for real seed runs (#747).
      oscal_log "OSCAL schema seed FAILED — bundle integrity check did not pass. " \
                "Re-run `bin/rails oscal:bundle_schemas` to refresh from NIST GitHub."
      exit 1
    end
  end

  # ── Network path (legacy / no-bundle deploy) ────────────────────────
  #
  # Fallback behavior when no schema bundle is present (pre-#453 image,
  # local dev without `bundle_schemas` ever run): NIST GitHub releases
  # → disk fallback → skip. Filenames match exactly between NIST,
  # the bundle, and the disk fallback as of #453, so no rename mapping
  # is required.
  def seed_from_network_with_disk_fallback
    disk_dir = Rails.root.join("lib", "oscal_schemas")

    stats = { downloaded: 0, disk_fallback: 0, skipped: 0, errors: 0 }

    oscal_log "OSCAL schema seed — network source (no bundle present)"

    OscalSchema::SUPPORTED_VERSIONS.each do |version|
      OscalSchema::DOCUMENT_TYPE_MAP.each do |doc_type, config|
        if doc_type == "mapping" && !OscalSchema::MAPPING_VERSIONS.include?(version)
          stats[:skipped] += 1
          next
        end

        label = "#{doc_type} v#{version}"
        raw_json = nil
        source_url = OscalSchema.nist_url(version, doc_type)

        begin
          body = fetch_following_redirects(source_url)
          raw_json = JSON.parse(body)
          oscal_log "  ✓ Downloaded #{label}"
          stats[:downloaded] += 1
        rescue StandardError => e
          oscal_log "  ✗ Download failed for #{label}: #{e.message} — trying disk fallback"
        end

        if raw_json.nil?
          disk_path = disk_dir.join(config[:file])
          if File.exist?(disk_path)
            raw_json = JSON.parse(File.read(disk_path))
            source_url = "file://#{disk_path}"
            oscal_log "  ↩ Disk fallback for #{label}: #{config[:file]}"
            stats[:disk_fallback] += 1
          else
            oscal_log "  ✗ No disk fallback for #{label} — skipping"
            stats[:errors] += 1
            next
          end
        end

        checksum = Digest::SHA256.hexdigest(raw_json.to_json)
        preprocessed = OscalSchema.preprocess_schema(raw_json)

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
    oscal_log ""
    oscal_log "OSCAL schema seed complete (network):"
    oscal_log "  Downloaded:    #{stats[:downloaded]}"
    oscal_log "  Disk fallback: #{stats[:disk_fallback]}"
    oscal_log "  Skipped:       #{stats[:skipped]}"
    oscal_log "  Errors:        #{stats[:errors]}"
    oscal_log "  Total in DB:   #{total}"
  end
end
