# Rake tasks for generating sample OSCAL artifacts from seeded data.
#
# Usage:
#   rails samples:generate          — generate all sample files
#   rails samples:generate_traditional — traditional NIST 800-53 only
#   rails samples:generate_20x      — FedRAMP 20x only
#
# Prerequisites: run `rails db:seed` first to populate the database.

namespace :samples do
  desc "Generate all sample OSCAL files from seeded data"
  task generate: :environment do
    Rake::Task["samples:generate_traditional"].invoke
    Rake::Task["samples:generate_20x"].invoke
    puts "\nAll sample files generated in samples/ directory."
  end

  desc "Generate traditional NIST 800-53 sample files"
  task generate_traditional: :environment do
    output_dir = Rails.root.join("samples/nist-traditional-demo")
    FileUtils.mkdir_p(output_dir)

    puts "Generating traditional NIST 800-53 sample OSCAL files..."

    # SSP
    if (ssp = SspDocument.find_by("name LIKE ?", "%ACME Cloud Platform%SSP%"))
      json = OscalSspExportService.new(ssp).export_unvalidated
      File.write(output_dir.join("ssp-acme-cloud.json"), json)
      puts "  Generated ssp-acme-cloud.json (#{json.bytesize} bytes)"
    else
      puts "  Skipped SSP — no ACME Cloud Platform SSP found"
    end

    # SAP
    if (sap = SapDocument.find_by("name LIKE ?", "%ACME Cloud Platform%Assessment Plan%"))
      json = OscalAssessmentPlanExportService.new(sap).export_unvalidated
      File.write(output_dir.join("sap-acme-cloud.json"), json)
      puts "  Generated sap-acme-cloud.json (#{json.bytesize} bytes)"
    else
      puts "  Skipped SAP — no ACME Cloud Platform SAP found"
    end

    # SAR
    if (sar = SarDocument.find_by("name LIKE ?", "%ACME Cloud Platform%Assessment%"))
      json = OscalSarExportService.new(sar).export_unvalidated
      File.write(output_dir.join("sar-acme-cloud.json"), json)
      puts "  Generated sar-acme-cloud.json (#{json.bytesize} bytes)"
    else
      puts "  Skipped SAR — no ACME Cloud Platform SAR found"
    end

    # POA&M
    if (poam = PoamDocument.find_by("name LIKE ?", "%ACME Cloud Platform%Plan of Action%"))
      json = OscalPoamExportService.new(poam).export_unvalidated
      File.write(output_dir.join("poam-acme-cloud.json"), json)
      puts "  Generated poam-acme-cloud.json (#{json.bytesize} bytes)"
    else
      puts "  Skipped POA&M — no ACME Cloud Platform POA&M found"
    end

    # CDEF
    if (cdef = CdefDocument.find_by("name LIKE ?", "%ACME Web Application Server%"))
      json = OscalComponentDefinitionExportService.new(cdef).export_unvalidated
      File.write(output_dir.join("cdef-web-server.json"), json)
      puts "  Generated cdef-web-server.json (#{json.bytesize} bytes)"
    else
      puts "  Skipped CDEF — no ACME Web Application Server CDEF found"
    end

    puts "  Traditional samples complete."
  end

  desc "Generate FedRAMP 20x sample files"
  task generate_20x: :environment do
    output_dir = Rails.root.join("samples/fedramp-20x-demo")
    FileUtils.mkdir_p(output_dir)

    puts "Generating FedRAMP 20x sample files..."

    # KSI Compliance Report
    boundary = AuthorizationBoundary.find_by(name: "Cloud Web Application ATO")
    if boundary && boundary.ksi_validations.any?
      service = KsiExportService.new(boundary)
      json = service.export(format: :json)
      File.write(output_dir.join("ksi-compliance-report.json"), json)
      puts "  Generated ksi-compliance-report.json (#{json.bytesize} bytes)"

      # Also generate YAML version
      yaml = service.export(format: :yaml)
      File.write(output_dir.join("ksi-compliance-report.yaml"), yaml)
      puts "  Generated ksi-compliance-report.yaml (#{yaml.bytesize} bytes)"
    else
      puts "  Skipped KSI report — no boundary with KSI validations found"
    end

    # Sample machine-readable evidence schema
    evidence_schema = {
      "fedramp-20x-evidence" => {
        "version" => "1.0.0",
        "remarks" => "DEMO/SAMPLE — Fictional machine-readable evidence schema for testing purposes only.",
        "evidence-items" => [
          {
            "ksi-id" => "ksi-mla-03",
            "title" => "Vulnerability Scan Results",
            "evidence-type" => "scan_result",
            "format" => "json",
            "collection-method" => "automated",
            "source" => "Trivy container scanner via GitHub Actions",
            "collected-at" => Time.current.iso8601,
            "data" => {
              "total-vulnerabilities" => 12,
              "critical" => 0,
              "high" => 2,
              "medium" => 7,
              "low" => 3,
              "scan-target" => "acme-cloud-app:latest",
              "scan-tool" => "trivy",
              "scan-tool-version" => "0.52.0"
            }
          },
          {
            "ksi-id" => "ksi-svc-02",
            "title" => "TLS Configuration Compliance",
            "evidence-type" => "config_export",
            "format" => "json",
            "collection-method" => "automated",
            "source" => "AWS Config rule: acm-certificate-expiration-check",
            "collected-at" => Time.current.iso8601,
            "data" => {
              "tls-minimum-version" => "TLSv1.2",
              "cipher-suites" => %w[TLS_AES_256_GCM_SHA384 TLS_CHACHA20_POLY1305_SHA256],
              "certificate-valid" => true,
              "certificate-expiry" => (Time.current + 180.days).iso8601,
              "hsts-enabled" => true
            }
          },
          {
            "ksi-id" => "ksi-scr-02",
            "title" => "Software Bill of Materials",
            "evidence-type" => "artifact",
            "format" => "cyclonedx-json",
            "collection-method" => "automated",
            "source" => "CycloneDX generator in CI/CD pipeline",
            "collected-at" => Time.current.iso8601,
            "data" => {
              "sbom-format" => "CycloneDX 1.5",
              "total-components" => 247,
              "direct-dependencies" => 42,
              "transitive-dependencies" => 205,
              "licenses-identified" => 238,
              "licenses-unknown" => 9
            }
          }
        ]
      }
    }

    json = JSON.pretty_generate(evidence_schema)
    File.write(output_dir.join("ksi-validation-evidence.json"), json)
    puts "  Generated ksi-validation-evidence.json (#{json.bytesize} bytes)"

    puts "  FedRAMP 20x samples complete."
  end
end
