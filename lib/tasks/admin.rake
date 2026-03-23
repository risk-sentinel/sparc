# frozen_string_literal: true

# Standalone admin bootstrap — runs independently of db:seed.
# Called from bin/docker-entrypoint on every web container start.
# Idempotent: creates admin if missing, fixes admin flag if unset,
# attaches avatar if missing. NEVER resets existing passwords.
#
# NIST IA-4: Identifier Management
# NIST AC-2: Account Management
namespace :sparc do
  desc "Bootstrap admin account (idempotent — never resets existing passwords)"
  task bootstrap_admin: :environment do
    unless SparcConfig.enable_local_login?
      puts "[AdminBootstrap] Skipped — local login not enabled (SPARC_ENABLE_LOCAL_LOGIN)."
      next
    end

    email = ENV.fetch("SPARC_ADMIN_EMAIL", "admin@sparc.local")
    admin = User.find_or_initialize_by(email: email.downcase.strip)

    if admin.new_record? || !admin.password_digest.present?
      # New install or password was never set — generate initial password
      password = SecureRandom.alphanumeric(20)
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
          metadata: { email: admin.email }
        )

        puts ""
        puts "=" * 60
        puts "  SPARC Admin Account #{admin.previously_new_record? ? 'Created' : 'Reset'}"
        puts "=" * 60
        puts "  Email:    #{admin.email}"
        if Rails.env.production?
          puts "  Password: [REDACTED — check container logs on first run only]"
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
    else
      # Admin exists with a password — ensure admin flag is set
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
