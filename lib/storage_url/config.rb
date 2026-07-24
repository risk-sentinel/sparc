# frozen_string_literal: true

require "uri"

# #785 Pass 2.1 — one variable for object storage: SPARC_STORAGE_URL.
#
# Collapses ACTIVE_STORAGE_SERVICE + AWS_BUCKET into a single, self-documenting
# URL whose scheme picks the provider — mirroring how DATABASE_URL drives the
# database (lib/db_url/config.rb). The common AWS case is one line:
#
#   SPARC_STORAGE_URL=s3://my-bucket            # region ← AWS_REGION
#   SPARC_STORAGE_URL=s3://my-bucket?region=X   # explicit region
#   (unset)                                     # local disk
#
# Region is NOT crammed into the identifier: an S3 bucket name doesn't carry a
# region, so it resolves URL ?region= → AWS_REGION → us-east-1 — the same
# precedence idea as the DB work, and consistent with AWS_REGION being the
# SDK-wide region var.
#
# Back-compat: with SPARC_STORAGE_URL unset, the legacy ACTIVE_STORAGE_SERVICE +
# AWS_BUCKET path still works unchanged — this reduces what must be SET, not what
# works.
#
# Providers: S3 and local are what SPARC supports today (only aws-sdk-s3 is
# bundled). The scheme space is designed to extend to azure:// / gcs:// once
# their gems + storage.yml services are added.
#
# Required by config/application.rb before the app class is defined, so the
# constant exists when config/storage.yml renders (storage.yml is pre-autoload,
# like database.yml). Lives in an autoload-ignored lib subdir; no app/ deps.
module StorageUrl
  DEFAULT_REGION = "us-east-1"

  extend self

  # The raw SPARC_STORAGE_URL, or nil when unset/blank.
  def raw = ENV.fetch("SPARC_STORAGE_URL", nil)&.strip.presence

  def configured? = !raw.nil?

  def uri
    return nil unless configured?

    URI.parse(raw)
  rescue URI::InvalidURIError
    nil
  end

  # The Active Storage service name (a symbol matching a config/storage.yml key).
  #   SPARC_STORAGE_URL scheme → provider; else legacy ACTIVE_STORAGE_SERVICE;
  #   else local. Production + local is guarded by the boot posture check.
  def service
    if configured?
      case uri&.scheme
      when "s3" then :amazon
      when nil then :local # unparseable — posture check will flag it
      else uri.scheme.to_sym # azure/gcs future
      end
    elsif (legacy = ENV.fetch("ACTIVE_STORAGE_SERVICE", nil).presence)
      legacy.to_sym
    else
      :local
    end
  end

  def local? = service == :local

  # S3 bucket: the URL host (s3://BUCKET), else legacy AWS_BUCKET.
  def bucket
    if configured? && uri&.scheme == "s3"
      uri.host
    else
      ENV.fetch("AWS_BUCKET", nil).presence
    end
  end

  # Region precedence: URL ?region= → AWS_REGION → default.
  def region
    from_url = uri && URI.decode_www_form(uri.query || "").to_h["region"]
    from_url.presence || ENV.fetch("AWS_REGION", nil).presence || DEFAULT_REGION
  end
end
