# frozen_string_literal: true

# NIST 800-53 Controls:
#   SI-3  Malicious Code Protection (executable + content-type rejection)
#   SI-10 Information Input Validation (extension allowlist, declared-vs-actual type)
#   CM-7  Least Functionality (no archive containers accepted)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
# #868 — the single source of truth for what may be uploaded as evidence.
#
# Before this existed the accepted types were an `accept` attribute on the
# dropzone plus matching client-side JS. Both are browser hints: switching the
# file picker to "All Files" bypasses them, and so does any direct POST. There
# was no server-side allowlist at all, and the web controller — unlike the API —
# never ran the executable-signature check, so an .exe or a shell script could
# be stored as evidence through the browser.
#
# This class is deliberately callable from both the UI and Api::V1 controllers
# so the two paths cannot drift again. The form's `accept` attribute is
# generated from the same constant that the server enforces, so what we
# advertise and what we accept are the same list by construction.
#
# Three layers, cheapest first:
#   1. Extension allowlist   — is this a type we accept at all?
#   2. Executable signature  — magic bytes of a program, whatever it is named
#   3. Declared vs actual    — do the bytes match the extension claimed?
#
# Layer 3 is what stops "rename evil.sh to report.pdf". Marcel reads the file
# directly and ignores the client-supplied Content-Type header.
class EvidenceUploadPolicy
  # Raised for any rejection. Reuses FileUploadable's error so the API's
  # existing `rescue FileUploadable::UploadRejectedError` keeps working and
  # there is one error type across every upload path.
  Error = FileUploadable::UploadRejectedError

  TEXT_PLAIN = "text/plain"

  # Formats with reliable magic bytes. These are verified from CONTENT ALONE —
  # Marcel is called WITHOUT the `name:` hint, so the filename cannot vouch for
  # the bytes. That is what makes "rename evil.sh to report.pdf" fail here.
  #
  # Measured 2026-07-30: passing `name:` makes Marcel fall back to the extension
  # for anything lacking strong magic bytes, so a text payload named .pdf is
  # reported as application/pdf. Passing the hint would defeat the check it is
  # supposed to perform. (FileUploadable#validate_content_type! passes `name:`
  # and its comment claims renaming cannot bypass it — true only for formats
  # with strong magic bytes, which is worth revisiting on the import path.)
  MAGIC_VERIFIED_TYPES = {
    ".pdf"  => [ "application/pdf" ],
    ".png"  => [ "image/png" ],
    ".jpg"  => [ "image/jpeg" ],
    ".jpeg" => [ "image/jpeg" ],
    ".gif"  => [ "image/gif" ],
    ".xlsx" => %w[application/vnd.openxmlformats-officedocument.spreadsheetml.sheet application/zip],
    ".xls"  => %w[application/vnd.ms-excel application/x-ole-storage]
  }.freeze

  # Text formats. Sniffed on content alone like everything else, but they must
  # allow application/octet-stream because that is what ordinary text reports
  # as when no filename hint is given.
  #
  # That still buys real protection rather than nothing: measured 2026-07-30,
  # every strong-magic payload gets a SPECIFIC type when read bytes-only — PE32
  # application/x-msdownload, ELF application/x-elf, zip application/zip, PDF
  # application/pdf. So a binary renamed to .log is rejected here even though
  # genuine log text passes. What cannot be discriminated is text-from-text,
  # which the executable-signature check covers for the case that matters.
  OCTET_STREAM = "application/octet-stream"

  TEXT_LIKE_TYPES = {
    ".csv"  => [ OCTET_STREAM, "text/csv", "application/csv", TEXT_PLAIN ],
    ".json" => [ OCTET_STREAM, "application/json", "text/json", TEXT_PLAIN ],
    ".xml"  => [ OCTET_STREAM, "application/xml", "text/xml", TEXT_PLAIN ],
    ".txt"  => [ OCTET_STREAM, TEXT_PLAIN ],
    ".log"  => [ OCTET_STREAM, TEXT_PLAIN, "text/x-log" ],
    ".html" => [ OCTET_STREAM, "text/html", TEXT_PLAIN ]
  }.freeze

  TEXT_LIKE_EXTENSIONS = TEXT_LIKE_TYPES.keys.freeze

  # `.zip` is deliberately absent from both. A container tells you nothing about
  # what is inside: its extension and content-type are satisfied by any payload,
  # it defeats the executable and content checks for the actual content, and it
  # is a zip-bomb vector. Evidence is downloaded by assessors onto their own
  # machines, so SPARC is a distribution point — "we don't execute it" is not
  # the control.
  ALLOWED_EXTENSIONS = (MAGIC_VERIFIED_TYPES.keys + TEXT_LIKE_EXTENSIONS).freeze

  # Drives the dropzone's `accept` attribute so the advertised list and the
  # enforced list are the same thing.
  def self.accept_attribute
    ALLOWED_EXTENSIONS.join(",")
  end

  def self.human_extension_list
    ALLOWED_EXTENSIONS.join(", ")
  end

  # Raises EvidenceUploadPolicy::Error with a message written for the person
  # who has to fix the upload, not for a log.
  def self.validate!(uploaded_file)
    return if uploaded_file.blank?

    filename = uploaded_file.try(:original_filename).to_s
    ext      = File.extname(filename).downcase

    if ext.blank?
      raise Error, "File rejected: #{filename.presence || 'the upload'} has no file extension. " \
                   "Accepted types: #{human_extension_list}."
    end

    unless ALLOWED_EXTENSIONS.include?(ext)
      raise Error, "File rejected: #{ext} is not an accepted evidence type. " \
                   "Accepted types: #{human_extension_list}."
    end

    # Path-bearing uploads only. A metadata-only create, or a test double
    # without a tempfile, has no bytes to inspect and nothing to reject.
    return unless uploaded_file.respond_to?(:path) && uploaded_file.path.present?

    reject_executable!(uploaded_file, filename)
    reject_content_mismatch!(uploaded_file, filename, ext)
  end

  # Layer 2 — a program is a program whatever it is called. Shares the
  # signature table with FileUploadable so there is one list to maintain.
  def self.reject_executable!(uploaded_file, filename)
    header = File.binread(uploaded_file.path, 32).to_s
    FileUploadable::EXECUTABLE_MAGIC_BYTES.each do |signature, description|
      next unless header.start_with?(signature)

      raise Error, "File rejected: #{filename} contains #{description}. " \
                   "Executable content is not permitted as evidence."
    end
  end

  # Layer 3 — for magic-byte formats only, the bytes must match the extension.
  #
  # Marcel is called WITHOUT `name:` on purpose: the filename is the thing under
  # suspicion, so it does not get to vouch for the content. Text-like
  # extensions are skipped because content sniffing cannot distinguish them
  # (see TEXT_LIKE_EXTENSIONS) — claiming otherwise would be a check that only
  # appears to check.
  def self.reject_content_mismatch!(uploaded_file, filename, ext)
    expected = MAGIC_VERIFIED_TYPES[ext] || TEXT_LIKE_TYPES[ext]
    return if expected.nil?

    actual = File.open(uploaded_file.path, "rb") { |io| Marcel::MimeType.for(io) }
    return if expected.include?(actual)

    raise Error, "File rejected: #{filename} is named #{ext} but its contents are #{actual}. " \
                 "The extension must match the actual file type."
  end

  private_class_method :reject_executable!, :reject_content_mismatch!
end
