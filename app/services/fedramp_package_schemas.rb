# frozen_string_literal: true

require "digest"
require "json"

# FedRAMP's machine-readable package schemas (Consolidated Rules for 2026),
# vendored byte for byte under lib/data/fedramp/schemas/ with their provenance
# in lib/data/fedramp/fedramp-schemas.provenance.json (#1354, #1384).
#
# FedRAMP rule FRC-CSO-JSN: package JSON must validate against FedRAMP's
# schema. This class loads those schemas, proves each file is the pinned one,
# and resolves the schemas' cross-file `$ref`s (they name each other by their
# https://fedramp.gov/schemas/... `$id`) to the local copies. Validation never
# reaches the network.
#
# NIST SP 800-53: SI-7 (software and information integrity — every schema file
# is checked against its pinned SHA-256 before use), SR-4 (provenance),
# SI-10 (information input validation).
class FedrampPackageSchemas
  class Error < StandardError; end

  DIR = Rails.root.join("lib/data/fedramp/schemas").freeze
  PROVENANCE = Rails.root.join("lib/data/fedramp/fedramp-schemas.provenance.json").freeze

  # The shared definitions every other schema refers to. It describes no
  # document of its own, so it is never a document type.
  COMMON = "common-definitions"

  Schema = Struct.new(:document_type, :file, :id, :version, :title, :sha256, :document, keyword_init: true)

  class << self
    # Every vendored schema, by document type ("certification-package-overview",
    # "vulnerability-detail-report", ...). Raises if any file is not the
    # pinned one.
    def all
      @all ||= load_all.freeze
    end

    def document_types = all.keys - [ COMMON ]

    def fetch(document_type)
      all.fetch(document_type.to_s) do
        raise Error, "Unknown FedRAMP document type '#{document_type}'. Known: #{document_types.join(', ')}"
      end
    end

    # The schema whose `$id` the document names in `$schema`, or nil.
    def for_schema_uri(uri)
      wanted = normalize_uri(uri)
      all.values.find { |s| normalize_uri(s.id) == wanted && s.document_type != COMMON }
    end

    # A `ref_resolver` for json_schemer: any https://fedramp.gov/schemas/...
    # URI resolves to the local copy, and anything else is refused.
    def ref_resolver
      by_id = all.values.to_h { |s| [ normalize_uri(s.id), s.document ] }
      lambda do |uri|
        by_id.fetch(normalize_uri(uri.to_s.sub(/#.*\z/, ""))) do
          raise Error, "FedRAMP schema reference #{uri} is not one of the vendored schemas"
        end
      end
    end

    def schemer(document_type)
      @schemers ||= {}
      @schemers[document_type.to_s] ||= JSONSchemer.schema(fetch(document_type).document,
                                                           ref_resolver: ref_resolver, format: true)
    end

    def reset! = (@all = @schemers = nil)

    # www.fedramp.gov and fedramp.gov name the same schema; the $ids use the
    # bare host and the published copies the www one.
    def normalize_uri(uri) = uri.to_s.strip.sub(%r{\Ahttps?://(www\.)?}, "https://").chomp("/")

    private

    def load_all
      pins = JSON.parse(File.read(PROVENANCE)).fetch("files")
      on_disk = Dir[DIR.join("*.json")].map { |p| File.basename(p) }.sort
      unpinned = on_disk - pins.keys
      raise Error, "FedRAMP schema file(s) with no pin in #{PROVENANCE.basename}: #{unpinned.join(', ')}" if unpinned.any?

      pins.to_h do |file, pin|
        raw = File.binread(DIR.join(file))
        actual = Digest::SHA256.hexdigest(raw)
        unless actual == pin.fetch("sha256")
          raise Error, "#{file}: SHA-256 #{actual} does not match the pinned #{pin['sha256']}"
        end

        doc = JSON.parse(raw)
        type = file[/\Afedramp-(.+)-schema-\d{4}-\d{2}-\d{2}\.json\z/, 1] or
          raise Error, "#{file}: not a FedRAMP schema file name"
        [ type, Schema.new(document_type: type, file: file, id: doc.fetch("$id"),
                           version: doc["$schemaVersion"], title: doc["title"], sha256: actual, document: doc) ]
      end
    end
  end
end
