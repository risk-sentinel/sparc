# frozen_string_literal: true

require "rails_helper"

# #785 — configuration drift check.
#
# The problem this exists to solve: production values live in sparc-iac's ECS
# task definition, defaults live here in SparcConfig, and NOTHING ever compared
# the two. That is how the task definition accumulated ~46 entries that merely
# restated a default, plus two that set "" over a working default and silently
# broke the feature.
#
# This is deliberately NOT a manifest. A manifest would be a second source of
# truth that has to be kept in parity with the 120 accessors already in
# SparcConfig. Instead this reads the real task definition and compares it
# against the real compiled defaults, so it cannot drift from either.
#
# It REPORTS redundancy. It never asserts that a variable should not exist —
# "not required" is not "deleted", and a variable matching its default remains a
# perfectly valid, supported override.
#
# The task definition lives in a sibling repo, so this skips when absent
# (CI, contributor checkouts). Point SPARC_TASK_DEF_PATH at it to run.
RSpec.describe "ECS task definition drift", :drift do
  DEFAULT_PATH = "../sparc-iac/AWS/ECS/envs/prod/sparc-task-definition.json"

  # Values Terraform renders — never comparable to a default.
  TERRAFORM_TOKEN = /\$\{.*\}/

  # Deliberate per-deployment values. Listing them here is the point: anything
  # NOT listed and NOT differing from its default is drift worth reporting.
  INTENTIONAL = %w[
    RAILS_ENV SPARC_APP_URL SPARC_ADMIN_EMAIL SPARC_CONTACT_EMAIL
    SPARC_OIDC_CLIENT_ID SPARC_OIDC_ISSUER_URL SPARC_OIDC_PROVIDER_TITLE
    SPARC_GITHUB_CLIENT_ID SPARC_ORG_NAME SPARC_ORG_DESCRIPTION
    SPARC_HEADER_TEXT SPARC_BANNER_MESSAGE SPARC_ENABLE_LOCAL_LOGIN
    SPARC_API_AUTH SPARC_AWS_LABS_CDEF_ENABLED
    SPARC_SMTP_ADDRESS SPARC_SMTP_USERNAME SPARC_SMTP_FROM_ADDRESS
    SPARC_SMTP_PORT SPARC_SMTP_AUTH
    ACTIVE_STORAGE_SERVICE SOLID_QUEUE_IN_PUMA
  ].freeze

  # Accessors whose name does not mechanically follow from the variable.
  ALIASES = {
    "SPARC_ENABLE_USER_REGISTRATION" => :enable_registration?,
    "SPARC_CCI_REVS" => :cci_revisions,
    "SPARC_SESSION_TIMEOUT_MINUTES" => :session_timeout
  }.freeze

  let(:task_def_path) do
    ENV["SPARC_TASK_DEF_PATH"].presence || Rails.root.join(DEFAULT_PATH).to_s
  end

  let(:environment) do
    JSON.parse(File.read(task_def_path)).fetch("environment")
  end

  # An on-demand audit, not a permanently red spec. It reports work that is
  # pending in a SIBLING repo (trimming the task definition), so failing the
  # default suite would be reporting someone else's to-do list as our breakage.
  # Run it with:  SPARC_DRIFT_CHECK=1 bundle exec rspec spec/config
  before do
    skip "set SPARC_DRIFT_CHECK=1 to run the drift audit" unless ENV["SPARC_DRIFT_CHECK"] == "1"
    skip "task definition not found at #{task_def_path} — set SPARC_TASK_DEF_PATH" \
      unless File.exist?(task_def_path)
  end

  # Reads the compiled default by asking SparcConfig with the variable unset.
  # Asking the real accessor is what keeps this honest: there is no second list
  # to maintain, and a default changed in code is picked up automatically.
  def default_for(var, accessor)
    original = ENV[var]
    ENV.delete(var)
    value = SparcConfig.public_send(accessor)
    value.is_a?(Array) ? value.join(",") : value.to_s
  ensure
    original.nil? ? ENV.delete(var) : ENV[var] = original
  end

  # var => accessor. Only vars with a SparcConfig accessor can be compared;
  # boot-file reads (puma, database.yml) have no accessor and are skipped.
  COMPARABLE = {
    "SPARC_APP_NAME" => :app_name,
    "SPARC_WELCOME_TEXT" => :welcome_text,
    "SPARC_INACTIVITY_DAYS" => :inactivity_days,
    "SPARC_PASSWORD_EXPIRY_DAYS" => :password_expiry_days,
    "SPARC_SA_INACTIVITY_DAYS" => :sa_inactivity_days,
    "SPARC_SESSION_TIMEOUT_MINUTES" => :session_timeout,
    "SPARC_PROCESSING_STUCK_MINUTES" => :processing_stuck_minutes,
    "SPARC_MAX_UPLOAD_MB" => :max_upload_mb,
    "SPARC_MAX_AVATAR_MB" => :max_avatar_mb,
    "SPARC_LDAP_PORT" => :ldap_port,
    "SPARC_OIDC_SCOPES" => :oidc_scopes,
    "SPARC_GITLAB_SITE" => :gitlab_site,
    "SPARC_CCI_REVS" => :cci_revisions,
    "SPARC_RATE_LIMIT_UPLOADS_PER_5MIN_PER_IP" => :rate_limit_uploads_per_5min_per_ip,
    "SPARC_RATE_LIMIT_UPLOADS_PER_HOUR_PER_USER" => :rate_limit_uploads_per_hour_per_user,
    "SPARC_RATE_LIMIT_API_WRITES_PER_MINUTE" => :rate_limit_api_writes_per_minute,
    "SPARC_RATE_LIMIT_LOGIN_FAILURES_PER_MIN" => :rate_limit_login_failures_per_minute
  }.freeze

  it "reports entries whose value merely restates the compiled default" do
    redundant = COMPARABLE.filter_map do |var, accessor|
      next unless environment.key?(var)

      value = environment[var].to_s
      next if value.match?(TERRAFORM_TOKEN)

      default = default_for(var, accessor)
      "#{var}=#{value.inspect} (default is already #{default.inspect})" if value == default
    end

    expect(redundant).to be_empty, <<~MSG
      #{redundant.size} task-definition entries set a value identical to the
      shipped default. They can be deleted — the variable stays supported, it
      simply need not be set:

        #{redundant.join("\n  ")}
    MSG
  end

  # The defect class that actually broke production twice: "" is not nil, so
  # ENV.fetch(k, default) returns "" and the default never fires.
  it "reports entries set to an empty string that would defeat a real default" do
    blanked = COMPARABLE.filter_map do |var, accessor|
      next unless environment[var] == ""

      default = default_for(var, accessor)
      "#{var}=\"\" but the default is #{default.inspect}" if default.present?
    end

    expect(blanked).to be_empty, <<~MSG
      These are set to "" over a non-empty default. An empty string is not nil,
      so the default never fires and the feature is silently disabled:

        #{blanked.join("\n  ")}
    MSG
  end

  it "flags variables the application no longer reads anywhere" do
    known = COMPARABLE.keys + INTENTIONAL
    unknown = environment.keys.reject do |var|
      known.include?(var) ||
        environment[var].to_s.match?(TERRAFORM_TOKEN) ||
        var.start_with?("RAILS_", "AWS_", "SPARC_DB_", "SPARC_LDAP_", "SPARC_SMTP_") ||
        SparcConfig.respond_to?(accessor_guess(var)) ||
        SparcConfig.respond_to?("#{accessor_guess(var)}?") ||
        ALIASES.key?(var) ||
        boot_only?(var)
    end

    expect(unknown).to be_empty, <<~MSG
      These task-definition entries match no SparcConfig accessor and no known
      boot-file variable. Verify each is still read by something — HTTP_PORT,
      RAILS_SERVE_STATIC_FILES and ACTIVE_STORAGE_SERVICE were all found to be
      read by nothing during #785:

        #{unknown.join("\n  ")}
    MSG
  end

  # SPARC_FOO_BAR -> :foo_bar / :foo_bar?  (best-effort, for the unknown check)
  def accessor_guess(var)
    var.sub(/\ASPARC_/, "").downcase
  end

  BOOT_ONLY = %w[
    PORT HTTP_PORT MALLOC_ARENA_MAX SOLID_QUEUE_IN_PUMA FORCE_SSL
    DATABASE_URL REDIS_URL SECRET_KEY_BASE ACTIVE_STORAGE_SERVICE
    SPARC_RUN_SEEDS SPARC_SEED_MODE SPARC_SKIP_DEFERRED_DATA_MIGRATIONS
    SPARC_ALLOW_CRED_ROTATION SPARC_PRINT_ROTATED_PASSWORD
    SPARC_ADMIN_CREDENTIALS_SECRET_ARN SPARC_AWS_SECRETS_ENABLED
    SPARC_APP_CONFIG_SECRET_ARN SPARC_AWS_IAM_DB_AUTH SPARC_LOG_LEVEL
  ].freeze

  def boot_only?(var) = BOOT_ONLY.include?(var)
end
