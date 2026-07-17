# Local-validation override (#742 UBI9 smoke): production.rb hardcodes S3
# (:amazon). For local runs with no AWS, force disk storage so the app boots.
Rails.application.config.active_storage.service = :local
