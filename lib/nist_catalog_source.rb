# frozen_string_literal: true

# NistCatalogSource — the one definition of where SPARC's bundled NIST SP 800-53
# Rev 5 catalog comes from (#1228).
#
# The seed, the ODP worksheets, the catalog screen's pre-release flag, the data
# migration that repairs existing installs and the drift and release checks all
# read the catalog through here, so the vendored XML, its generated JSON and the
# provenance that describes them cannot be named three different ways.
#
#   NistCatalogSource.xml_path    — NIST's XML source, vendored unchanged
#   NistCatalogSource.json_path   — the JSON generated from it (committed)
#   NistCatalogSource.provenance  — the sidecar: repo, branch, commit, sha256, …
#   NistCatalogSource.pre_release? — true while the catalog comes from NIST's
#                                   develop branch rather than a NIST release
#
# Regenerate the JSON with `bin/rails catalog:build_rev5`;
# spec/lib/nist_catalog_source_spec.rb fails when the committed file drifts.
#
# NIST 800-53: SI-7 (information integrity — pinned sha256), CM-3 (change
# control of the bundled catalog). See: docs/compliance/nist-sp800-53-rev5-mapping.md
module NistCatalogSource
  DIR = "lib/data/catalogs"
  XML = "NIST_SP-800-53_rev5_catalog.xml"
  JSON_FILE = "NIST_SP-800-53_rev5_catalog.json"
  PROVENANCE = "NIST_SP-800-53_rev5_catalog.provenance.json"

  # Every document uuid NIST has given the Rev 5 catalog that SPARC has
  # bundled. NIST mints a new one per revision, so an install seeded from the
  # v5.2.0 file carries the first and a fresh install the second; both are the
  # same NIST catalog.
  RELEASED_V5_2_0_UUID = "5ba2a3ba-1aa2-47d8-ad69-5beef7372b98"
  DEVELOP_UUID = "ea7c7688-79c5-463b-a91b-0650f2d98623"
  CATALOG_UUIDS = [ RELEASED_V5_2_0_UUID, DEVELOP_UUID ].freeze

  module_function

  def root = defined?(Rails) ? Rails.root : Pathname(__dir__).parent

  def xml_path = root.join(DIR, XML)

  def json_path = root.join(DIR, JSON_FILE)

  def provenance_path = root.join(DIR, PROVENANCE)

  def provenance
    @provenance ||= JSON.parse(provenance_path.read).freeze
  end

  def pre_release? = provenance["pre_release"] == true

  def source_commit = provenance["source_commit"]

  # The JSON exactly as committed: converted, pretty-printed, newline-terminated.
  def render(xml = xml_path.read)
    "#{JSON.pretty_generate(OscalCatalogXmlToJson.convert(xml))}\n"
  end

  def build!
    json_path.write(render)
  end

  # The catalog, parsed, from the committed JSON.
  def catalog
    JSON.parse(json_path.read)
  end

  # Is this ControlCatalog NIST's Rev 5 catalog as SPARC bundles it?
  def bundled?(control_catalog)
    uuid = control_catalog.oscal_uuid.presence ||
           control_catalog.metadata_extra.to_h["catalog_uuid"]
    CATALOG_UUIDS.include?(uuid)
  end

  RELEASE_DATA = "spec/fixtures/files/catalogs/nist_oscal_content_releases.json"

  def release_data_path = root.join(RELEASE_DATA)

  # The NIST releases that mean the pre-release catalog should be replaced:
  # one that carries the pinned commit, or one published after the commit whose
  # contents were never checked. `record` is what
  # `bin/rails catalog:check_nist_release` wrote; the suite never calls GitHub.
  def releases_requiring_action(record)
    commit_date = record["fix_commit_date"].presence && Time.iso8601(record["fix_commit_date"])
    Array(record["releases"]).select do |release|
      next true if release["contains_fix_commit"] == true
      next false unless release["contains_fix_commit"].nil?

      commit_date.nil? || release["published_at"].blank? || Time.iso8601(release["published_at"]) > commit_date
    end
  end

  # Does this catalog row carry NIST's unreleased develop content? True for a
  # catalog imported from the develop file (its uuid says so) and for an older
  # install whose rows FixRev5DevelopCatalogParts patched (its stamp says so).
  # False for everything once the provenance stops calling the source
  # pre-release, which is the whole of "dropping the flag".
  def pre_release_catalog?(control_catalog)
    return false unless pre_release? && control_catalog

    extra = control_catalog.metadata_extra.to_h
    control_catalog.oscal_uuid == DEVELOP_UUID ||
      extra["catalog_uuid"] == DEVELOP_UUID ||
      extra["nist_develop_patch"].present?
  end
end
