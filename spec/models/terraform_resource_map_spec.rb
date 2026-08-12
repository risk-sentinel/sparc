# frozen_string_literal: true

require "rails_helper"

# #904 — the mapping table ported from sparc-iac's state_cdef_coverage.py.
#
# First match wins, so ORDER is the correctness story. These examples are the
# cases where a naive `aws_<namespace>_` split gets the answer wrong; they are
# the reason the table exists rather than being derived.
RSpec.describe TerraformResourceMap do
  describe ".service_for — the order-dependent cases" do
    it "reads aws_cloudwatch_event_* as EventBridge, not CloudWatch" do
      expect(described_class.service_for("aws_cloudwatch_event_rule")).to eq("eventbridge")
      expect(described_class.service_for("aws_cloudwatch_event_target")).to eq("eventbridge")
    end

    it "still reads other aws_cloudwatch_* as CloudWatch" do
      expect(described_class.service_for("aws_cloudwatch_log_group")).to eq("cloudwatch")
      expect(described_class.service_for("aws_cloudwatch_metric_alarm")).to eq("cloudwatch")
    end

    it "reads aws_db_* as RDS, which is spelled nothing like its service" do
      expect(described_class.service_for("aws_db_instance")).to eq("rds")
      expect(described_class.service_for("aws_db_subnet_group")).to eq("rds")
      expect(described_class.service_for("aws_rds_cluster")).to eq("rds")
    end

    it "reads the three load-balancer spellings as elb" do
      expect(described_class.service_for("aws_lb")).to eq("elb")
      expect(described_class.service_for("aws_lb_target_group")).to eq("elb")
      expect(described_class.service_for("aws_elb")).to eq("elb")
      expect(described_class.service_for("aws_alb_listener")).to eq("elb")
    end

    it "gathers the networking cluster under vpc despite unrelated-looking names" do
      %w[aws_vpc aws_subnet aws_route_table aws_route aws_internet_gateway
         aws_nat_gateway aws_network_acl aws_security_group aws_flow_log
         aws_egress_only_internet_gateway].each do |type|
        expect(described_class.service_for(type)).to eq("vpc"), "expected #{type} to map to vpc"
      end
    end

    it "reads the autoscaling launch primitives as autoscaling" do
      expect(described_class.service_for("aws_launch_template")).to eq("autoscaling")
      expect(described_class.service_for("aws_autoscaling_group")).to eq("autoscaling")
    end

    it "reads aws_scheduler_* as EventBridge Scheduler" do
      expect(described_class.service_for("aws_scheduler_schedule")).to eq("eventbridge")
    end

    it "distinguishes waf spellings" do
      expect(described_class.service_for("aws_wafv2_web_acl")).to eq("waf")
      expect(described_class.service_for("aws_waf_rule")).to eq("waf")
    end
  end

  describe ".service_for — when nothing matches" do
    it "returns nil for an AWS type the table does not know" do
      expect(described_class.service_for("aws_quicksight_dashboard")).to be_nil
    end

    it "returns nil for a provider with no rules yet" do
      expect(described_class.service_for("azurerm_storage_account")).to be_nil
      expect(described_class.service_for("google_compute_instance")).to be_nil
    end

    it "returns nil rather than raising on junk" do
      expect(described_class.service_for("")).to be_nil
      expect(described_class.service_for(nil)).to be_nil
    end
  end

  # The owner's call on #904: an unmapped resource is a coverage GAP, not just a
  # hole in this table. A wholly non-AWS boundary must not report zero gaps.
  describe ".inferred_service_for" do
    it "derives a namespaced key from Terraform's own naming convention" do
      expect(described_class.inferred_service_for("azurerm_storage_account")).to eq("azurerm:storage")
      expect(described_class.inferred_service_for("google_compute_instance")).to eq("google:compute")
      expect(described_class.inferred_service_for("aws_quicksight_dashboard")).to eq("aws:quicksight")
    end

    it "namespaces the key so an inferred name cannot be mistaken for a known one" do
      expect(described_class.inferred_service_for("aws_ecs_service")).to include(":")
      expect(described_class.known_service_keys.grep(/:/)).to be_empty
    end

    it "returns nil when there is no service segment to infer from" do
      expect(described_class.inferred_service_for("aws")).to be_nil
      expect(described_class.inferred_service_for("")).to be_nil
      expect(described_class.inferred_service_for(nil)).to be_nil
    end
  end

  describe ".known_service_keys" do
    it "matches the AWS Labs CDEF basenames the index resolves against" do
      # Sampled against the real corpus (24 files in awslabs/oscal-content-for-aws-services).
      expect(described_class.known_service_keys).to include(
        "acm", "cloudtrail", "cloudwatch", "config", "ecr", "ecs", "elb", "eventbridge",
        "guardduty", "iam", "kms", "lambda", "rds", "route53", "s3", "secretsmanager",
        "serverlessrepo", "ses", "sns", "sqs", "ssm", "waf"
      )
    end

    it "is deduplicated and sorted" do
      keys = described_class.known_service_keys
      expect(keys).to eq(keys.uniq.sort)
    end
  end
end
