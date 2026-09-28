# FedRAMP 20x Key Security Indicators (KSIs) catalog.
#
# #1115 / #1172 — built from what FedRAMP publishes, not transcribed by hand.
# The source is the vendored FedRAMP/rules snapshot in lib/data/fedramp
# (provenance in its sidecar); FedrampKsiImportService validates it against
# FedRAMP's own JSON Schema, builds Catalog -> theme (ControlFamily) ->
# indicator (CatalogControl), and the KSI -> NIST SP 800-53 Rev 5 crosswalk from
# each indicator's `controls[]`.
#
# The same import is `bin/rails ksi:import` and POST /api/v1/ksi_catalog/import.
# It is a no-op when the catalog already carries this snapshot, and it re-keys a
# catalog seeded by the previous hand-written version of this file in place,
# retiring (never deleting) indicators FedRAMP no longer publishes.
#
# Run with: bin/rails db:seed

puts "Seeding FedRAMP 20x KSI catalog from FedRAMP's consolidated rules..."

result = FedrampKsiImportService.new.call
puts result.report.lines.map { |l| "  #{l}" }.join
raise "FedRAMP KSI import refused" if result.refused?

puts "Done! FedRAMP 20x KSI catalog seeded."
