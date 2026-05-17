require "net/http"
require "json"
require "uri"

# Issue #466 — Thin GitHub HTTP client for the AWS Labs OSCAL content repo.
# Single responsibility: discover CDEF files in the repo and fetch blob content
# via the Trees + Blobs APIs. Uses ETag conditional GET so the daily refresh
# is near-zero cost when nothing has changed.
#
# Why not Octokit?
#   The dependency chain isn't worth it for two endpoints. Net::HTTP + JSON
#   is in stdlib and what most other internal SPARC services use (cf.
#   OscalSchemaValidationService).
#
# NIST mapping: SR-3 (Supply Chain Controls — content integrity via blob SHA),
# RA-3(1) (Supply Chain Risk Assessment — external source enumeration).
class AwsLabsCdefSourceClient
  class Error < StandardError; end
  class RateLimitedError < Error; end
  class NotFoundError < Error; end

  GITHUB_API_HOST = "api.github.com"
  ETAG_CACHE_NAMESPACE = "aws_labs_cdef:etag"
  ETAG_CACHE_TTL = 7.days

  def initialize(repo: SparcConfig.aws_labs_cdef_repo,
                 branch: SparcConfig.aws_labs_cdef_branch,
                 token: SparcConfig.aws_labs_github_token,
                 logger: Rails.logger)
    @repo = repo
    @branch = branch
    @token = token.presence
    @logger = logger
  end

  # Returns an Array of file entries from the recursive Trees API:
  #   [{ path:, sha:, type: "blob", url:, size: }, ...]
  # Filtered to .json files under component-definitions/. Returns nil if the
  # cached ETag matches (server reports 304 Not Modified) — caller can treat
  # that as "nothing changed since last run."
  def list_component_definition_files
    path = "/repos/#{@repo}/git/trees/#{@branch}?recursive=1"
    cache_key = "#{ETAG_CACHE_NAMESPACE}:tree:#{@repo}:#{@branch}"
    cached_etag = Rails.cache.read(cache_key)

    response = get(path, headers: cached_etag ? { "If-None-Match" => cached_etag } : {})

    case response.code.to_i
    when 304
      @logger.info("[AwsLabsCdefSourceClient] Tree unchanged (ETag #{cached_etag})")
      nil
    when 200
      new_etag = response["etag"]
      Rails.cache.write(cache_key, new_etag, expires_in: ETAG_CACHE_TTL) if new_etag

      body = JSON.parse(response.body)
      tree = body.fetch("tree", [])
      tree.select do |entry|
        entry["type"] == "blob" &&
          entry["path"].start_with?("component-definitions/") &&
          entry["path"].end_with?(".json")
      end
    when 403, 429
      raise RateLimitedError, "GitHub API rate limit hit: #{response.body}"
    when 404
      raise NotFoundError, "Repo or branch not found: #{@repo}@#{@branch}"
    else
      raise Error, "Unexpected GitHub API response: #{response.code} #{response.body}"
    end
  end

  # Fetch raw blob content for a file entry. Uses the Contents API rather than
  # the Blobs API because Contents returns the html_url and download_url we
  # want to record in import_metadata.source_url. Returns:
  #   { path:, sha:, html_url:, content: <String of raw bytes> }
  def fetch_file(path:)
    response = get("/repos/#{@repo}/contents/#{path}?ref=#{@branch}")
    raise NotFoundError, "File not found: #{path}" if response.code.to_i == 404
    raise RateLimitedError, "GitHub API rate limit hit" if response.code.to_i == 403
    raise Error, "Unexpected response: #{response.code}" unless response.code.to_i == 200

    body = JSON.parse(response.body)
    content =
      if body["encoding"] == "base64" && body["content"].present?
        Base64.decode64(body["content"])
      else
        # Fall back to the download_url (large files / submodules)
        fetch_raw(body.fetch("download_url"))
      end

    {
      path: body["path"],
      sha: body["sha"],
      html_url: body["html_url"],
      content: content
    }
  end

  # Resolve the current commit SHA the branch points at. Recorded in
  # import_metadata.source_commit_sha so an audit can pin any imported row
  # to the exact upstream snapshot.
  def current_commit_sha
    response = get("/repos/#{@repo}/commits/#{@branch}")
    raise Error, "Failed to resolve commit: #{response.code}" unless response.code.to_i == 200
    JSON.parse(response.body).fetch("sha")
  end

  private

  def get(path, headers: {})
    uri = URI("https://#{GITHUB_API_HOST}#{path}")
    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/vnd.github+json"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    request["User-Agent"] = "sparc-aws-labs-cdef-import"
    request["Authorization"] = "Bearer #{@token}" if @token
    headers.each { |k, v| request[k] = v }

    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.read_timeout = 30
      http.open_timeout = 10
      http.request(request)
    end
  end

  # Some blobs are larger than the Contents API base64 limit (~1MB) and the
  # response inlines a download_url instead of content. Fetch raw from there.
  def fetch_raw(url)
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.read_timeout = 30
      response = http.get(uri.request_uri)
      raise Error, "Raw fetch failed: #{response.code}" unless response.code.to_i == 200
      response.body
    end
  end
end
