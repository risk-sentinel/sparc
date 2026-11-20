# frozen_string_literal: true

# DEMO: the FedRAMP sample package as received documents (#1354, #1384).
#
# Loads the valid documents of samples/fedramp-package-demo/ (its manifest's
# list) into the demo boundary, through ReceivedDocumentService, exactly as an
# upload arrives: validated, stored once, waiting for a reviewer. Nobody is
# recorded as the uploader, so separation of duties does not withhold the
# review from any seeded reviewer.
#
# Idempotent: a stream that already holds a document's bytes reports it
# unchanged and stores nothing, so a re-run adds nothing.
fedramp_samples = Rails.root.join("samples/fedramp-package-demo")
fedramp_boundary = AuthorizationBoundary.find_by(name: "Cloud Web Application ATO")

if fedramp_boundary
  manifest = JSON.parse(File.read(fedramp_samples.join("manifest.json")))
  outcomes = manifest.fetch("documents").map do |entry|
    ReceivedDocumentService.call(
      boundary: fedramp_boundary, bytes: File.binread(fedramp_samples.join(entry.fetch("file"))),
      source: "upload", filename: entry.fetch("file"), content_type: "application/json", received_by: nil
    )
  end
  stored = outcomes.count(&:stored?)
  invalid = outcomes.count { |o| o.document.state == "invalid" }
  puts "  FedRAMP sample package: #{stored} stored, #{outcomes.size - stored} already held " \
       "(#{fedramp_boundary.name}, Received documents)"
  raise ReceivedDocumentService::Error, "FedRAMP sample package: #{invalid} document(s) failed validation" if invalid.positive?
else
  puts "  Skipped the FedRAMP sample package: no demo boundary (set SPARC_SEED_DEMO=true)."
end
