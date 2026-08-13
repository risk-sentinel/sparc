# frozen_string_literal: true

FactoryBot.define do
  factory :cdef_coverage_run do
    analyzed_at { Time.current }
    source_files { [ { "filename" => "prod.tfstate", "digest" => "0" * 64, "format" => "state", "resource_count" => 1 } ] }
    unmapped_resource_types { [] }
  end

  factory :cdef_coverage_result do
    association :cdef_coverage_run
    service_key { "ecs" }
    verdict { "adopt" }
    resource_count { 1 }
    resource_types { [ "aws_ecs_service" ] }
  end

  factory :cdef_service_alias do
    service_key { "nginx" }
    always_keep { true }
  end
end
