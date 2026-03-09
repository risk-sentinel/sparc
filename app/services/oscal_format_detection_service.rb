# Detects the format of an OSCAL document by file extension or content sniffing.
#
# Usage:
#   result = OscalFormatDetectionService.detect(filename: "ssp.yaml")
#   result.format       # => :yaml
#   result.detected_by  # => :extension
#
#   result = OscalFormatDetectionService.detect(content: '{"system-security-plan": ...}')
#   result.format       # => :json
#   result.detected_by  # => :content
#
class OscalFormatDetectionService
  Result = Struct.new(:format, :detected_by, keyword_init: true)

  EXTENSION_MAP = {
    ".json" => :json,
    ".yaml" => :yaml,
    ".yml"  => :yaml,
    ".xml"  => :xml
  }.freeze

  SUPPORTED_FORMATS = %i[json yaml xml].freeze

  # Detect format from filename/path and/or raw content.
  #
  # @param file_path [String, nil]  path to the file (extension used for detection)
  # @param filename  [String, nil]  original filename (extension used for detection)
  # @param content   [String, nil]  raw file content (used for content sniffing)
  # @return [Result]  with :format (:json, :yaml, :xml) and :detected_by (:extension, :content)
  # @raise [ArgumentError] if no format can be determined
  def self.detect(file_path: nil, filename: nil, content: nil)
    # 1. Try extension-based detection first
    name = filename || file_path
    if name.present?
      ext = File.extname(name).downcase
      fmt = EXTENSION_MAP[ext]
      return Result.new(format: fmt, detected_by: :extension) if fmt
    end

    # 2. Fall back to content sniffing
    if content.present?
      fmt = sniff_content(content)
      return Result.new(format: fmt, detected_by: :content) if fmt
    end

    raise ArgumentError, "Unable to detect OSCAL format. Provide a file with a recognized extension (.json, .yaml, .yml, .xml) or valid content."
  end

  # Content-sniff the format from raw file content.
  #
  # @param content [String] raw file content
  # @return [Symbol, nil] :json, :yaml, :xml, or nil
  def self.sniff_content(content)
    stripped = content.lstrip
    first_char = stripped[0]

    case first_char
    when "{", "["
      :json
    when "<"
      :xml
    else
      # If it looks like YAML (key: value pairs, document start marker, etc.)
      :yaml if stripped.match?(/\A(---|[\w-]+\s*:)/)
    end
  end

  private_class_method :sniff_content
end
