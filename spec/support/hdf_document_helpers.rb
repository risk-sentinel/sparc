# frozen_string_literal: true

# #1354 — HDF documents for ingest specs, built to pass `hdf validate`.
#
# HdfIngestService validates every upload with the pinned hdf CLI, so a spec's
# HDF has to be a real HDF v2 (InSpec exec-json) document. The v2 schema
# requires fields SPARC never reads (statistics, platform.release, a profile's
# sha256/supports/attributes/groups, a control's refs/tags/source_location, a
# result's code_desc/start_time); these builders supply them, so a spec states
# only the fields it is about.
module HdfDocumentHelpers
  HDF_V2_START_TIME = "2026-06-01T00:00:00Z"

  # One v2 control. `results:` overrides the single result built from `status:`.
  # Pass `impact: nil` for a control that carries no impact.
  def hdf_v2_control(id, status: "failed", impact: 0.7, severity: nil, title: "Title #{id}",
                     desc: "Desc #{id}", tags: {}, results: nil)
    tags = tags.merge("severity" => severity) if severity
    control = {
      "id" => id, "title" => title, "desc" => desc, "refs" => [], "tags" => tags,
      "code" => "", "source_location" => { "ref" => "controls/#{id}.rb", "line" => 1 },
      "results" => results || [ hdf_v2_result(status) ]
    }
    control["impact"] = impact unless impact.nil?
    control
  end

  def hdf_v2_result(status, code_desc: "check #{status}")
    { "status" => status, "code_desc" => code_desc, "start_time" => HDF_V2_START_TIME }
  end

  # One v2 results document with a single profile named after the scanner.
  def hdf_v2_doc(controls, scanner: "trivy", version: "1.2.3", platform: "test-platform")
    {
      "platform" => { "name" => platform, "release" => "1.0" },
      "version" => "5.22.3",
      "statistics" => { "duration" => 0.1 },
      "profiles" => [ {
        "name" => scanner, "version" => version, "sha256" => "0" * 64,
        "supports" => [], "attributes" => [], "groups" => [],
        "controls" => controls
      } ]
    }
  end
end

RSpec.configure do |config|
  config.include HdfDocumentHelpers
end
