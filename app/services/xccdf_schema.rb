# frozen_string_literal: true

require "digest"
require "json"
require "tmpdir"

# The XCCDF 1.2 schema (NIST SCAP) and the schemas it imports, vendored byte for
# byte under lib/data/xccdf/1.2/ with their provenance in
# lib/data/xccdf/xccdf.provenance.json (#1354).
#
# The NIST files import their dependencies from absolute locations
# (https://www.w3.org/2009/01/xml.xsd, /schema/cpe/2.3/...). The files stay
# verbatim; when the schema is loaded, each import's schemaLocation is pointed
# at the local copy, in memory, and libxml2 is told not to use the network.
#
# NIST SP 800-53: SI-7 (each file checked against its pinned SHA-256), SR-4
# (provenance), SI-10 (input validation).
class XccdfSchema
  class Error < StandardError; end

  NAMESPACE = "http://checklists.nist.gov/xccdf/1.2"
  VERSION = "1.2"
  DIR = Rails.root.join("lib/data/xccdf/1.2").freeze
  PROVENANCE = Rails.root.join("lib/data/xccdf/xccdf.provenance.json").freeze
  ROOT_FILE = "xccdf_1.2.xsd"
  XSD_NS = { "xsd" => "http://www.w3.org/2001/XMLSchema" }.freeze

  class << self
    def schema
      @schema ||= build
    end

    def sha256 = provenance.dig("files", ROOT_FILE, "sha256")

    # Schema errors for a parsed document, as strings. Errors only; the
    # caller decides what a document with none means.
    def validate(document)
      schema.validate(document).map { |e| "line #{e.line}: #{e.message.strip}" }
    end

    def reset! = (@schema = @provenance = nil)

    private

    def provenance
      @provenance ||= JSON.parse(File.read(PROVENANCE))
    end

    def build
      files = provenance.fetch("files")
      imports = provenance.fetch("imports")

      Dir.mktmpdir("xccdf-schema-") do |dir|
        files.each do |file, pin|
          raw = File.binread(DIR.join(file))
          actual = Digest::SHA256.hexdigest(raw)
          raise Error, "#{file}: SHA-256 #{actual} does not match the pinned #{pin['sha256']}" unless actual == pin["sha256"]

          doc = Nokogiri::XML(raw) { |config| config.strict.nonet }
          doc.xpath("//xsd:import | //xsd:include", XSD_NS).each do |node|
            local = imports.fetch(node["schemaLocation"]) do
              raise Error, "#{file} imports #{node['schemaLocation']}, which has no local copy in #{PROVENANCE.basename}"
            end
            # An absolute path, so nothing depends on the process's working
            # directory (Dir.chdir is process-wide and unsafe under Puma).
            node["schemaLocation"] = File.join(dir, local)
          end
          File.write(File.join(dir, file), doc.to_xml)
        end

        Nokogiri::XML::Schema(File.read(File.join(dir, ROOT_FILE)), Nokogiri::XML::ParseOptions.new.strict.nonet)
      end
    end
  end
end
