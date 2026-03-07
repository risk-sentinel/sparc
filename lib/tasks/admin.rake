# frozen_string_literal: true

namespace :sparc do
  desc "Bootstrap or regenerate the admin account password"
  task bootstrap_admin: :environment do
    email = ENV.fetch("SPARC_ADMIN_EMAIL", "admin@sparc.local")
    password = SecureRandom.alphanumeric(20)

    admin = User.find_or_initialize_by(email: email.downcase.strip)
    admin.assign_attributes(
      password: password,
      password_confirmation: password,
      display_name: "SPARC Admin",
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
      puts "  SPARC Admin Account"
      puts "=" * 60
      puts "  Email:    #{admin.email}"
      puts "  Password: #{password}"
      puts ""
      puts "  *** Save this password — it will not be shown again ***"
      puts "  You will be required to change it on first login."
      puts "=" * 60
      puts ""
    else
      puts "ERROR: Could not create admin: #{admin.errors.full_messages.join(', ')}"
    end
  end
end
