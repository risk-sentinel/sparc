# frozen_string_literal: true

# Raised by the document parser services (SSP / SAR / SAP / POA&M / CDEF /
# Profile, JSON + XML) when an uploaded document is structurally invalid or
# missing a required OSCAL root element.
#
# A StandardError subclass, so the existing `rescue StandardError` in
# DocumentConversionJob and FileUploadable still catches it and surfaces
# `.message` unchanged. This is the behavior-preserving replacement for the
# former bare `raise "..."` (RuntimeError) calls flagged by SonarCloud
# rubydre:S7815 — no rescue in the app matches RuntimeError specifically, so
# the raised class changes but the caught-and-reported behavior does not.
class DocumentParseError < StandardError; end
