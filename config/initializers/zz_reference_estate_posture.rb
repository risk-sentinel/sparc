# frozen_string_literal: true

# #845 — say so, loudly and permanently, when a production instance is carrying
# reference fixture data.
#
# The estate is deliberately loadable into a production-MODE instance, because
# that is what an authenticated DAST run targets and DAST needs full documents.
# The cost of allowing it is that someone can now look at a production screen
# and see authorization documents that are not real. The mitigation is not to
# ban it again — it is to make sure nobody has to guess.
#
# Same shape as zz_storage_posture.rb: a warning rather than a hard fail,
# because the estate is opt-in and self-identifying (every record it owns is
# named "Reference …"), whereas silent data loss is not recoverable.
#
# NIST 800-53: CM-6 (configuration settings), AU-12 (audit record generation),
# SA-11 (developer testing — the fixture exists to be tested against).
Rails.application.config.after_initialize do
  # `assets:precompile` boots the production environment purely to build assets
  # (Rails signals that with SECRET_KEY_BASE_DUMMY). There is no database wired
  # there, so a posture check that queries one aborts the image build — the
  # trap zz_storage_posture.rb documents.
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?
  next unless Rails.env.production?

  begin
    next unless ActiveRecord::Base.connection.table_exists?(:authorization_boundaries)

    tier = ReferenceEstate.loaded_tier
    next if tier.blank?

    Rails.logger.warn(
      "[SPARC] REFERENCE ESTATE LOADED in production (tier=#{tier}, " \
      "#{ReferenceEstateBuilder::PRODUCTION_OPT_IN}). This instance carries FIXTURE " \
      "authorization documents — two organizations named \"Reference …\" with a full " \
      "SSP/SAP/SAR/POA&M chain. They are not real authorizations and must not be " \
      "treated as evidence. Remove with: bin/rails db:seed:reference:purge"
    )
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished,
         ActiveRecord::StatementInvalid => e
    # A boot that cannot reach the database has bigger problems than this
    # check, and the check must never be the thing that fails the boot.
    Rails.logger.debug { "[SPARC] reference-estate posture check skipped: #{e.class}" }
  end
end
