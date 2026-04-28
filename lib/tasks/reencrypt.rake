# frozen_string_literal: true

# Re-encrypts FederationPeer credentials after a SPARC_HASH rotation (#419).
# See docs/SPARC_HASH_ROTATION.md for the full operator runbook.
#
# Production invocation (no ECS Exec required) — operator uses
# `aws ecs run-task` with command + env overrides on the existing app
# task definition; see the runbook for the exact CLI invocation.
#
# Local / non-prod invocation:
#   OLD_SPARC_HASH='<previous master value>' bundle exec rails sparc:reencrypt:rotate_master_key
namespace :sparc do
  namespace :reencrypt do
    desc "Re-encrypt FederationPeer credentials after a SPARC_HASH rotation (#419)"
    task rotate_master_key: :environment do
      old_master = ENV["OLD_SPARC_HASH"].to_s

      result = FederationPeerReencryptionService.call(old_master: old_master)

      unless result.success?
        msg = result.error
        msg += " (peer id: #{result.error_peer_id})" if result.error_peer_id
        abort "[SparcHashRotation] FAILED: #{msg}"
      end

      AuditEvent.log(
        action: "sparc_hash_rotated",
        metadata: {
          peer_count_total: FederationPeer.count,
          rotated_count:    result.rotated.size,
          skipped_count:    result.skipped.size,
          old_hash_fingerprint: result.old_fingerprint,
          new_hash_fingerprint: result.new_fingerprint
        }
      )

      puts ""
      puts "=" * 60
      puts "  SPARC_HASH Rotation Complete"
      puts "=" * 60
      puts "  Rotated:  #{result.rotated.size} peer(s)"
      puts "  Skipped:  #{result.skipped.size} peer(s) (already on current key)"
      result.rotated.each do |entry|
        puts "    - #{entry[:name]} (id #{entry[:peer_id]}): #{entry[:fields].join(', ')}"
      end
      puts "=" * 60
      puts ""
    end
  end
end
