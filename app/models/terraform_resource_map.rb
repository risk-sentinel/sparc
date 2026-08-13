# frozen_string_literal: true

# #904 — Terraform resource type to service key.
#
# Ported from `sparc-iac/oscal/scripts/state_cdef_coverage.py` (sparc-iac#287),
# which is where these rules were learned against real state. The CLI around
# them is sparc-iac's CI concern and stays there; this table is the part worth
# moving.
#
# ── Order is the correctness story ────────────────────────────────────────
#
# First match wins, so specific rules MUST precede general ones.
# `aws_cloudwatch_event_rule` is EventBridge, not CloudWatch — put the general
# `^aws_cloudwatch_` rule first and every EventBridge resource is silently
# mis-attributed. The same trap applies to the vpc cluster, which matches a
# dozen unrelated-looking prefixes (`subnet`, `route_table`, `nat_`,
# `flow_log`), and to rds, which owns `aws_db_*` rather than anything spelled
# "rds".
#
# A naive `aws_<namespace>_` split gets roughly ten of these wrong, which is why
# the table exists rather than being derived.
#
# ── Adding a provider ─────────────────────────────────────────────────────
#
# Rules are namespaced by Terraform provider prefix. AWS is populated because
# that is the corpus SPARC has (#466 ingests AWS Labs CDEFs weekly). `azurerm`
# and `google` are declared empty deliberately: their resources are then
# reported as UNMAPPED with their real type names rather than silently dropped,
# so the gap is visible and the table can be grown from what operators actually
# deploy. Adding a provider is a table addition, not a redesign.
class TerraformResourceMap
  # Ordered [pattern, service key]. Service keys match AWS Labs CDEF basenames
  # (`component-definitions/<key>.oscal.json`), which is what CdefServiceIndex
  # resolves against.
  AWS_RULES = [
    [ /\Aaws_acm_/, "acm" ],
    [ /\Aaws_cloudtrail/, "cloudtrail" ],
    [ /\Aaws_cloudwatch_event/, "eventbridge" ],   # EventBridge under its legacy name
    [ /\Aaws_scheduler_/, "eventbridge" ],         # EventBridge Scheduler
    [ /\Aaws_cloudwatch_/, "cloudwatch" ],         # must follow the two above
    [ /\Aaws_config_/, "config" ],
    [ /\Aaws_(lb|elb|alb)(\z|_)/, "elb" ],
    [ /\Aaws_ecr_/, "ecr" ],
    [ /\Aaws_ecs_/, "ecs" ],
    [ /\Aaws_elasticache_/, "elasticache" ],
    [ /\Aaws_guardduty_/, "guardduty" ],
    [ /\Aaws_iam_/, "iam" ],
    [ /\Aaws_kms_/, "kms" ],
    [ /\Aaws_lambda_/, "lambda" ],
    [ /\Aaws_(db_|rds_)/, "rds" ],
    [ /\Aaws_route53_/, "route53" ],
    [ /\Aaws_s3_/, "s3" ],
    [ /\Aaws_secretsmanager_/, "secretsmanager" ],
    [ /\Aaws_ses_/, "ses" ],
    [ /\Aaws_sns_/, "sns" ],
    [ /\Aaws_sqs_/, "sqs" ],
    [ /\Aaws_ssm_/, "ssm" ],
    [ /\Aaws_(wafv2_|waf_)/, "waf" ],
    [ /\Aaws_(vpc(\z|_)|subnet|route_table|route(\z|_)|internet_gateway|nat_|network_|
         default_security_group|security_group|flow_log|egress_only)/x, "vpc" ],
    [ /\Aaws_(autoscaling_|launch_template|launch_configuration)/, "autoscaling" ],
    [ /\Aaws_serverlessapplicationrepository_/, "serverlessrepo" ]
  ].freeze

  RULES_BY_PROVIDER = {
    "aws" => AWS_RULES,
    "azurerm" => [].freeze,
    "google" => [].freeze
  }.freeze

  # The provider prefix of a resource type: `aws_ecs_service` => "aws".
  def self.provider_for(resource_type)
    resource_type.to_s.split("_", 2).first.presence
  end

  # Service key for a resource type, or nil when no rule matches.
  #
  # nil is a reportable outcome, not a failure — see TerraformInventory#add.
  def self.service_for(resource_type)
    rules = RULES_BY_PROVIDER[provider_for(resource_type)]
    return nil if rules.blank?

    # `find`, not `each` with an early return: the intent IS first-match-wins,
    # and saying so directly keeps the ordering contract legible.
    rules.find { |pattern, _service| pattern.match?(resource_type) }&.last
  end

  def self.supported_providers = RULES_BY_PROVIDER.keys.select { |p| RULES_BY_PROVIDER[p].present? }

  # A provisional service key for a type no rule matched.
  #
  # #904 (owner call) — an unmapped resource is a coverage GAP, not merely a
  # hole in this table. A boundary running entirely on Azure must not report
  # zero gaps, because zero gaps reads as full coverage.
  #
  # Terraform's own convention is `<provider>_<service>_<resource>`, so the
  # middle segment is the service the provider itself claims. That is an
  # inference, not knowledge, which is why the key is namespaced
  # (`azurerm:storage`) and every consumer marks it `inferred` — a reader must
  # be able to tell a derived name from one the table actually knows.
  #
  # Returns nil for a type with no discernible service segment, which stays
  # unmapped-only rather than becoming an invented gap.
  def self.inferred_service_for(resource_type)
    provider, remainder = resource_type.to_s.split("_", 2)
    return nil if provider.blank? || remainder.blank?

    service = remainder.split("_").first
    return nil if service.blank?

    "#{provider}:#{service}"
  end

  # Every service key the table can produce. Used to sanity-check aliases and
  # to show an operator what the analyser is capable of recognising.
  def self.known_service_keys = AWS_RULES.map(&:last).uniq.sort
end
