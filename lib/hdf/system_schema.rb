# frozen_string_literal: true

require "json"
require "json_schemer"

module Hdf
  # #1179 — in-process validation of an hdf-system document against the
  # vendored v3.7.0 schema (lib/data/hdf/hdf-system.v3.7.0.schema.json).
  #
  # WHY A SECOND VALIDATOR WHEN THE CLI EXISTS
  #
  # `hdf validate --type system` is the authority, and HdfSystemExportService
  # runs it whenever the binary is present. It is NOT present on the CI test
  # runner (#835), so a spec that only asked the CLI would skip there and
  # prove nothing. The schema this class reads is byte-for-byte the one the
  # CLI embeds (see the provenance sidecar), so the two cannot disagree about
  # the rules — only about whether they were run.
  #
  # And where they WERE both run, they disagree. Measured on hdf-libs 3.7.0,
  # `hdf validate --type system` accepts a document with an undefined top-level
  # key and an `identifierScheme` of "not a uri": it does not enforce the
  # schema's `unevaluatedProperties: false`, nor the uri-reference format. It
  # does enforce enums, `minItems`, and the uuid and date-time formats. This
  # check enforces all of it, so it is the stricter of the two, not a copy.
  #
  # Draft 2020-12: an extra key, a value outside an enum, or an empty
  # `components` array is a hard failure, not a warning. The specs prove each
  # of those is rejected, because a validator that accepts everything is
  # indistinguishable from one that was never called (hdf-cli 3.5.1 gave four
  # false passes).
  module SystemSchema
    VERSION = "3.7.0"
    PATH = File.expand_path("../data/hdf/hdf-system.v#{VERSION}.schema.json", __dir__)

    module_function

    # A component whose `type` is wrong fails every branch of the oneOf, and
    # json_schemer reports each branch — 26 lines for one mistake. Capped so a
    # caller shown the list can still read it.
    MAX_ERRORS = 20

    # @return [Array<String>] "pointer: message" per violation (empty when valid)
    def errors(document)
      schemer.validate(document).map { |e|
        "#{e['data_pointer'].presence || '/'}: #{e['error']}"
      }.uniq.first(MAX_ERRORS)
    end

    def valid?(document) = errors(document).empty?

    # Compiled once per process: the bundled schema is 185 KB and every
    # primitive is an embedded resource, so compiling it per request would be
    # the expensive part of an export.
    def schemer
      @schemer ||= JSONSchemer.schema(JSON.parse(File.read(PATH)))
    end
  end
end
