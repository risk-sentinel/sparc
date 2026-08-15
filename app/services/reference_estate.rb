# frozen_string_literal: true

# #845 — lifecycle helpers for the reference leveraged authorization estate:
# what is loaded, how to describe it, and how to take it away again.
#
# ReferenceEstateBuilder creates the estate; this owns everything else, so the
# rake tasks, the seed section and the spec helper share one implementation of
# "which records belong to the estate" instead of each carrying their own list
# of names that would drift apart.
#
# The loaded tier is recorded in the leveraged boundary's `boundary_metadata`
# rather than a table of its own: the estate is already fully identified by its
# boundaries, and a migration for one string would be a poor trade.
module ReferenceEstate
  TIER_KEY = "reference_estate_tier"

  # Destroy order matters — children before the parents they point at, and
  # boundaries only after the documents referencing them are gone.
  class << self
    def loaded_tier
      leveraged_boundary&.boundary_metadata&.dig(TIER_KEY)
    end

    def loaded? = loaded_tier.present?

    def record_tier!(tier)
      boundary = leveraged_boundary
      return if boundary.nil?

      boundary.update!(boundary_metadata: boundary.boundary_metadata.merge(TIER_KEY => tier.to_s))
    end

    # The one way to load the estate. The rake task, the seed section and the
    # spec helper all come through here, so "replace a differing tier rather
    # than stack a second estate on top of it" is decided once. Three callers
    # each re-implementing that is three chances to get it wrong.
    def load!(tier, catalog: nil, verbose: true)
      tier = tier.to_sym
      unless ReferenceEstateBuilder::TIERS.include?(tier)
        raise ArgumentError,
              "unknown tier #{tier.inspect}, expected one of #{ReferenceEstateBuilder::TIERS.inspect}"
      end

      loaded = loaded_tier
      if loaded && loaded != tier.to_s
        puts "[reference] a #{loaded} estate is already loaded — replacing it with #{tier}." if verbose
        purge!
      end

      result = ReferenceEstateBuilder.new(tier: tier, catalog: catalog).build
      record_tier!(tier)
      result
    end

    def leveraged_boundary
      AuthorizationBoundary.find_by(name: ReferenceEstateBuilder::LEVERAGED_BOUNDARY)
    end

    def leveraging_boundary
      AuthorizationBoundary.find_by(name: ReferenceEstateBuilder::LEVERAGING_BOUNDARY)
    end

    def boundary_ids
      AuthorizationBoundary.where(name: [ ReferenceEstateBuilder::LEVERAGED_BOUNDARY,
                                          ReferenceEstateBuilder::LEVERAGING_BOUNDARY ]).pluck(:id)
    end

    # Returns a count per model so a caller can report what it removed rather
    # than claiming success blindly.
    def purge!
      raise ReferenceEstateBuilder::UnsafeEnvironment, "refusing to purge in production" if Rails.env.production?

      bids = boundary_ids
      counts = {}

      counts[:leveraged_authorizations] = LeveragedAuthorization.where(leveraging_boundary_id: bids).destroy_all.size
      counts[:scanner_findings] = ScannerFinding.where(authorization_boundary_id: bids).destroy_all.size
      counts[:scan_runs]        = ScanRun.where(authorization_boundary_id: bids).destroy_all.size
      counts[:evidence]         = (Evidence.where(authorization_boundary_id: bids).destroy_all.size +
                                   Evidence.where("title LIKE ?", like_prefix).destroy_all.size)
      counts[:poam_documents]   = named(PoamDocument).destroy_all.size
      counts[:sar_documents]    = named(SarDocument).destroy_all.size
      counts[:sap_documents]    = named(SapDocument).destroy_all.size
      counts[:ssp_documents]    = named(SspDocument).destroy_all.size

      # The boundary points at its profile, so break the reference before the
      # profile is destroyed or the FK refuses.
      AuthorizationBoundary.where(id: bids).update_all(profile_document_id: nil)
      counts[:profile_documents] = named(ProfileDocument).destroy_all.size
      counts[:boundaries]        = AuthorizationBoundary.where(id: bids).destroy_all.size
      counts[:organizations]     = Organization.where(name: [ ReferenceEstateBuilder::LEVERAGED_ORG,
                                                              ReferenceEstateBuilder::LEVERAGING_ORG ])
                                               .destroy_all.size
      counts
    end

    # One line per boundary, for `db:seed:reference:status`.
    def summary
      [ leveraged_boundary, leveraging_boundary ].compact.map do |boundary|
        ssp  = boundary.ssp_document
        sar  = boundary.sar_document
        open = sar&.sar_results&.first&.sar_risks&.count.to_i
        controls = ssp&.ssp_controls&.count.to_i

        "#{boundary.name}: controls=#{controls} open=#{open} " \
          "poams=#{boundary.poam_documents.count} " \
          "evidence=#{Evidence.where(authorization_boundary_id: boundary.id).count} " \
          "scans=#{ScanRun.where(authorization_boundary_id: boundary.id).count}"
      end
    end

    # ── Committed OSCAL artifacts ────────────────────────────────────────
    #
    # The estate is committed to the repo as OSCAL JSON so consumers can read
    # it without a database, and so regeneration proves the fixtures have not
    # drifted from the generators that produce them. `check!` is the drift
    # gate: regenerate into memory and compare against what is on disk.
    #
    # Exports go through the VALIDATED path, so regenerating also proves every
    # document still satisfies the OSCAL schema.
    EXPORTERS = {
      "ssp"  => [ :ssp,   OscalSspExportService ],
      "sap"  => [ :sap,   OscalAssessmentPlanExportService ],
      "sar"  => [ :sar,   OscalSarExportService ]
    }.freeze

    def fixture_root(tier) = Rails.root.join("db/fixtures/reference", tier.to_s)

    # { "leveraged-ssp.json" => "<json>", ... }
    def export_all
      artifacts = {}

      { "leveraged" => leveraged_boundary, "leveraging" => leveraging_boundary }.each do |role, boundary|
        next if boundary.nil?

        EXPORTERS.each do |kind, (_sym, service)|
          document = boundary.public_send(:"#{kind}_document")
          next if document.nil?

          artifacts["#{role}-#{kind}.json"] = service.new(document).export
        end

        boundary.poam_documents.order(:name).each do |poam|
          slug = poam.name[/\(([^)]+)\)\z/, 1].to_s.parameterize.presence || poam.id.to_s
          artifacts["#{role}-poam-#{slug}.json"] = OscalPoamExportService.new(poam).export
        end
      end

      artifacts
    end

    # Instance-level authoritative back-matter is embedded in EVERY export
    # regardless of relevance (#959), so regenerating from a working database
    # silently bakes unrelated resources into the committed artifacts — 96
    # leftover ui-smoke resources, the first time this ran. Refuse instead:
    # the artifacts are only trustworthy when generated from a clean instance.
    # `where.not(evidence_id: <ids>)` would silently miss every row with a NULL
    # evidence_id — `NULL NOT IN (...)` is NULL, not true — and those are
    # precisely the instance-level resources this needs to catch. Hence the
    # explicit IS NULL arm.
    def contaminating_resources
      BackMatterResource.active.where(source: "authoritative")
                        .where("evidence_id IS NULL OR evidence_id NOT IN (?)",
                               estate_evidence_ids.presence || [ -1 ])
    end

    def estate_evidence_ids
      Evidence.where(authorization_boundary_id: boundary_ids)
              .or(Evidence.where("title LIKE ?", like_prefix)).pluck(:id)
    end

    def regenerate!(tier)
      contaminants = contaminating_resources.pluck(:title).tally
      if contaminants.any?
        raise ReferenceEstateBuilder::UnsafeEnvironment,
              "refusing to regenerate: #{contaminants.values.sum} instance-level authoritative " \
              "back-matter resources would be embedded in every artifact " \
              "(#{contaminants.map { |t, n| "#{n}x #{t}" }.join(', ')}). " \
              "Regenerate from a clean, freshly seeded database. See #959."
      end

      root = fixture_root(tier)
      FileUtils.mkdir_p(root)

      artifacts = export_all
      # Remove artifacts that no longer regenerate, so a renamed or dropped
      # document leaves no stale file behind claiming to be current.
      (Dir.children(root).select { |f| f.end_with?(".json") } - artifacts.keys).each do |stale|
        File.delete(root.join(stale))
      end

      artifacts.each { |name, json| File.write(root.join(name), "#{json.chomp}\n") }
      artifacts.keys.sort
    end

    # Returns the artifacts whose regenerated content differs from disk, plus
    # anything missing or unexpected. Empty means no drift.
    def check(tier)
      root      = fixture_root(tier)
      artifacts = export_all
      on_disk   = Dir.exist?(root) ? Dir.children(root).select { |f| f.end_with?(".json") } : []

      differing = artifacts.filter_map do |name, json|
        path = root.join(name)
        next "#{name} (missing on disk)" unless File.exist?(path)

        File.read(path).chomp == json.chomp ? nil : "#{name} (content differs)"
      end

      differing + (on_disk - artifacts.keys).map { |f| "#{f} (on disk but not regenerated)" }
    end

    def report(result)
      puts "  tier: #{result.tier}"
      summary.each { |line| puts "  #{line}" }
      puts "  inheritance links: #{result.inheritance_links}"
    end

    private

    def named(klass) = klass.where("name LIKE ?", like_prefix)

    def like_prefix = "#{ReferenceEstateBuilder::NAME_PREFIX}%"
  end
end
