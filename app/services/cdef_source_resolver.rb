# #887 — get the original OSCAL back for a CDEF.
#
# The importer parses the source document into cdef_controls / cdef_control_fields
# and then discards it: the AWS Labs path writes to a Tempfile that goes out of
# scope, and nothing is attached. So reindexing cannot read what was imported —
# it has to resolve the source again.
#
# Two paths, because the two kinds of CDEF retain different things:
#
#   * uploaded / hand-authored -> the original upload is still attached
#   * AWS Labs                 -> nothing is retained, but import_metadata
#                                 records source_url, so re-fetch it
#
# Returns nil rather than raising when neither path is available. A CDEF with no
# recoverable source simply cannot be indexed, and that is a reportable state,
# not an error — see the `skipped` count in cdef:reindex.
class CdefSourceResolver
  # import_metadata stores the human-facing blob URL; raw.githubusercontent.com
  # serves the bytes.
  BLOB_URL = %r{\Ahttps://github\.com/(?<repo>[^/]+/[^/]+)/blob/(?<rest>.+)\z}

  def initialize(document, logger: Rails.logger)
    @document = document
    @logger = logger
  end

  def oscal
    from_attachment || from_source_url
  end

  private

  def from_attachment
    return nil unless @document.respond_to?(:file) && @document.file.attached?

    JSON.parse(@document.file.download)
  rescue JSON::ParserError, ActiveStorage::FileNotFoundError => e
    # A dangling blob (container rebuilt over a persistent DB) must not take the
    # whole reindex down — fall through to the source URL.
    @logger.warn("[CdefSourceResolver] attachment unusable for #{@document.id}: #{e.class}")
    nil
  end

  def from_source_url
    url = @document.import_metadata.is_a?(Hash) ? @document.import_metadata["source_url"] : nil
    return nil if url.blank?

    # get_response, not get: `get` returns the body String and would hide a 404
    # behind a JSON::ParserError. It does not follow redirects, so handle the
    # one hop raw.githubusercontent may issue.
    response = SparcHttp.get_response(URI(raw_url(url)))
    if response.is_a?(Net::HTTPRedirection) && response["location"].present?
      response = SparcHttp.get_response(URI(response["location"]))
    end

    unless response.is_a?(Net::HTTPSuccess)
      @logger.warn("[CdefSourceResolver] HTTP #{response.code} fetching #{url}")
      return nil
    end

    JSON.parse(response.body)
  rescue JSON::ParserError, StandardError => e
    @logger.warn("[CdefSourceResolver] #{e.class} fetching #{url}: #{e.message}")
    nil
  end

  def raw_url(url)
    match = BLOB_URL.match(url)
    return url unless match

    "https://raw.githubusercontent.com/#{match[:repo]}/#{match[:rest]}"
  end
end
