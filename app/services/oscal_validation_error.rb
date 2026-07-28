# frozen_string_literal: true

# Raised by OscalSchemaValidationService.validate! / validate_xml! when a
# document does not conform to its OSCAL schema.
#
# This lives in its own file so Zeitwerk can autoload it BY NAME. It used to be
# declared at the bottom of oscal_schema_validation_service.rb, which Zeitwerk
# expects to define only OscalSchemaValidationService. That worked as long as
# every reference sat inside a method body — resolved lazily, by which point the
# service file had been loaded for some other reason — but the first reference
# at class-body level (`rescue_from OscalValidationError` in
# Api::V1::TranslationsController, #831) failed to resolve under eager loading
# and took the whole boot down. It passed locally only because
# `config.eager_load` is off outside CI.
class OscalValidationError < StandardError; end
