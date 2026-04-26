# frozen_string_literal: true

# Standalone admin bootstrap — runs independently of db:seed.
# Called from bin/docker-entrypoint on every web container start.
# Idempotent: creates admin if missing, fixes admin flag if unset,
# attaches avatar if missing.
#
# Reconciles the admin password from `SPARC_ADMIN_PASSWORD` (typically
# injected by ECS from the admin-credentials Secrets Manager secret).
# When the env var is set and differs from the current bcrypt digest,
# the DB is updated to match — this is how rotations performed in SM
# (manually, by sparc-iac, or by the rotation Lambda) propagate into
# the running task on its next restart. See docs/dev/admin_credential_rotation.md
# and Rebel-Raiders/sparc-iac#197 for the full rotation flow.
#
# NIST IA-4: Identifier Management
# NIST IA-5: Authenticator Management (rotation propagation)
# NIST AC-2: Account Management
namespace :sparc do
  desc "Bootstrap admin account; reconcile password from SPARC_ADMIN_PASSWORD env if set"
  task bootstrap_admin: :environment do
    unless SparcConfig.enable_local_login?
      puts "[AdminBootstrap] Skipped — local login not enabled (SPARC_ENABLE_LOCAL_LOGIN)."
      next
    end

    email = ENV.fetch("SPARC_ADMIN_EMAIL", "admin@sparc.local")
    desired_password = ENV["SPARC_ADMIN_PASSWORD"].presence
    admin = User.find_or_initialize_by(email: email.downcase.strip)

    if admin.new_record? || !admin.password_digest.present?
      # New install or password was never set — prefer the SM-injected
      # value if available, else generate a random one and surface it
      # via container logs (operator captures it for the first login).
      password = desired_password || SecureRandom.alphanumeric(20)
      admin.assign_attributes(
        password: password,
        password_confirmation: password,
        display_name: admin.display_name.presence || "SPARC Admin",
        admin: true,
        status: "active",
        must_reset_password: true,
        password_changed_at: nil
      )

      if admin.save
        AuditEvent.log(
          user: admin,
          action: "admin_bootstrap",
          provider: "local",
          metadata: { email: admin.email,
                      source: desired_password ? "ecs_secrets_injection" : "generated" }
        )

        puts ""
        puts "=" * 60
        puts "  SPARC Admin Account #{admin.previously_new_record? ? 'Created' : 'Reset'}"
        puts "=" * 60
        puts "  Email:    #{admin.email}"
        if Rails.env.production?
          if desired_password
            puts "  Password: [from Secrets Manager — retrieve via AWS Console]"
          else
            puts "  Password: [REDACTED — check container logs on first run only]"
          end
        else
          puts "  Password: #{password}"
        end
        puts ""
        puts "  *** You will be required to change this password on first login. ***"
        puts "=" * 60
        puts ""
      else
        puts "[AdminBootstrap] ERROR: #{admin.errors.full_messages.join(', ')}"
      end
    elsif desired_password && !admin.authenticate(desired_password)
      # Existing admin, but the password injected by ECS (from SM AWSCURRENT)
      # no longer matches the DB — a rotation happened since this task last
      # started. Sync the DB so the running app uses the current password.
      # NIST IA-5: rotation propagation; AC-2: account state change audited.
      admin.update!(
        password: desired_password,
        password_confirmation: desired_password,
        must_reset_password: true,
        password_changed_at: Time.current
      )
      AuditEvent.log(
        user: admin,
        action: "admin_credential_synced_from_env",
        provider: "local",
        metadata: { email: admin.email, source: "ecs_secrets_injection" }
      )
      admin.update!(admin: true) unless admin.admin?
      puts "[AdminBootstrap] Synced admin password from SPARC_ADMIN_PASSWORD env (rotation detected)."
    else
      # Admin exists with a matching (or no env-supplied) password — only
      # ensure the admin flag is set.
      unless admin.admin?
        admin.update!(admin: true)
        puts "[AdminBootstrap] Fixed: admin flag set to true for #{admin.email}"
      end
      puts "[AdminBootstrap] Admin account exists (#{admin.email}) — no changes needed."
    end

    # Attach default avatar if not already set
    avatar_path = Rails.root.join("app/assets/images/sparc_admin.jpg")
    if admin.persisted? && !admin.avatar.attached? && File.exist?(avatar_path)
      admin.avatar.attach(
        io: File.open(avatar_path),
        filename: "sparc_admin.jpg",
        content_type: "image/jpeg"
      )
      puts "[AdminBootstrap] Admin avatar attached."
    end
  end

  desc "Rotate admin password and push to AWS Secrets Manager (#402)"
  task rotate_admin_credentials: :environment do
    unless Rails.env.production? || ENV["SPARC_ALLOW_CRED_ROTATION"] == "1"
      abort "Refusing to run outside production. Set SPARC_ALLOW_CRED_ROTATION=1 to override."
    end

    result = AdminCredentialRotationService.rotate_from_local!(
      source: "rake",
      admin_email: ENV.fetch("SPARC_ADMIN_EMAIL", nil)
    )

    if result.success?
      puts ""
      puts "=" * 60
      puts "  SPARC Admin Credentials Rotated"
      puts "=" * 60
      puts "  Version ID: #{result.version_id || '(SM push skipped)'}"
      if ENV["SPARC_PRINT_ROTATED_PASSWORD"] == "1"
        puts "  Password:   #{result[:plaintext]}"
        puts "  *** Save this password — it will not be shown again ***"
      else
        puts "  Password:   [retrieve from Secrets Manager via AWS Console]"
      end
      puts "=" * 60
      puts ""
    else
      abort "[RotateAdminCredentials] FAILED: #{result.error}"
    end
  end

  desc "Regenerate admin password (destructive — use only when needed)"
  task reset_admin_password: :environment do
    email = ENV.fetch("SPARC_ADMIN_EMAIL", "admin@sparc.local")
    admin = User.find_by(email: email.downcase.strip)

    unless admin
      puts "ERROR: No admin found with email #{email}"
      next
    end

    password = SecureRandom.alphanumeric(20)
    admin.update!(
      password: password,
      password_confirmation: password,
      must_reset_password: true,
      password_changed_at: nil
    )

    AuditEvent.log(
      user: admin,
      action: "admin_password_reset",
      provider: "local",
      metadata: { email: admin.email }
    )

    puts ""
    puts "=" * 60
    puts "  SPARC Admin Password Reset"
    puts "=" * 60
    puts "  Email:    #{admin.email}"
    puts "  Password: #{password}"
    puts ""
    puts "  *** Save this password — it will not be shown again ***"
    puts "=" * 60
    puts ""
  end
end
