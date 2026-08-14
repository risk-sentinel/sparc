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
