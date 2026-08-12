# frozen_string_literal: true

# #904 — read an uploaded Terraform file once: digest it, parse it, drop it.
#
# Exists so the raw bytes are handled in exactly one place. A state or plan can
# be tens of megabytes and both parsers plus format detection need the parsed
# document, so reading and parsing per-parser would mean doing it two or three
# times on content we are trying to keep short-lived.
#
# The digest is taken over the raw upload before parsing, so it identifies the
# file the operator actually submitted rather than a re-serialisation of it.
class TerraformDocumentReader
  Error = Class.new(StandardError)

  Document = Struct.new(:body, :digest, :filename, keyword_init: true) do
    # "state", "plan", or nil when it is neither.
    #
    # Detected from CONTENT, not the filename. Operators rename these files
    # constantly (`prod.tfstate.json`, `plan.json`), and a wrong parser chosen
    # from an extension fails with a confusing error about the wrong schema.
    def format
      return TerraformPlanInventoryService::FORMAT if body["resource_changes"].is_a?(Array)
      return TerraformStateInventoryService::FORMAT if body["resources"].is_a?(Array)

      nil
    end
  end

  def self.call(io:, filename:)
    raw = io.read.to_s
    digest = Digest::SHA256.hexdigest(raw)

    body =
      begin
        JSON.parse(raw)
      rescue JSON::ParserError => e
        # The parser message quotes the offending bytes, which in a state file
        # may be secret material. Report the position only, never the content.
        raise Error, "#{filename}: invalid JSON (#{e.message[/at line \d+ column \d+/] || 'unparseable'})"
      ensure
        raw = nil # rubocop:disable Lint/UselessAssignment -- drop the reference promptly
      end

    raise Error, "#{filename}: not a JSON object" unless body.is_a?(Hash)

    Document.new(body: body, digest: digest, filename: filename)
  end
end
