# Local UBI9 smoke setup (#742) — prepare the two smoke identities and print
# their API tokens for tests/api + ui-smoke.
#
#   docker compose -f docker-compose.ubi9.yaml exec -T web bin/rails runner - < dev/ubi9/smoke-setup.rb
#
# Why: bootstrap_admin seeds the admin with must_reset_password: true (correct
# for production — force a first-login password change). That 302s EVERY
# authenticated request to /password/edit, so the smoke identities must have it
# cleared or the whole suite bounces to the password page. The real deployment's
# service account isn't mid-reset, so this only matters for a locally-seeded image.
User.where(admin: true).update_all(must_reset_password: false, password_changed_at: Time.current)
admin = User.find_by(admin: true)

user = User.where(admin: false).first ||
       User.create!(email: "smoke-user@example.com",
                    password: "Password123!", password_confirmation: "Password123!",
                    admin: false)
User.where(admin: false).update_all(must_reset_password: false, password_changed_at: Time.current)

puts "SA=#{ApiToken.generate!(user: admin, name: 'smoke-sa').plaintext_token}"
puts "USER=#{ApiToken.generate!(user: user, name: 'smoke-user').plaintext_token}"
