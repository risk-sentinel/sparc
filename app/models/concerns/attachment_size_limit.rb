# frozen_string_literal: true

# Declarative ActiveStorage attachment size validation, sourced from a
# caller-supplied byte cap (typically a lambda reading SparcConfig at
# validation time so tests can stub the env-var-backed accessor without
# restarting Rails).
#
# Usage:
#   class CdefDocument < ApplicationRecord
#     include AttachmentSizeLimit
#     limit_attachment_size :file, max: -> { SparcConfig.max_upload_bytes }
#   end
#
#   class User < ApplicationRecord
#     include AttachmentSizeLimit
#     limit_attachment_size :avatar, max: -> { SparcConfig.max_avatar_bytes }
#   end
#
# The validation is a no-op when the attachment is not attached. When over
# limit, attaches a Rails-standard `errors.add` on the attachment field with
# a human-readable message including the actual size in MB.
module AttachmentSizeLimit
  extend ActiveSupport::Concern

  class_methods do
    def limit_attachment_size(attachment_name, max:)
      validate do
        next unless public_send(attachment_name).attached?

        size  = public_send(attachment_name).byte_size
        limit = max.respond_to?(:call) ? max.call : max
        next if size <= limit

        actual_mb = (size / 1.megabyte.to_f).round(2)
        limit_mb  = (limit / 1.megabyte.to_f).round(2)
        errors.add(
          attachment_name,
          "is too large (#{actual_mb} MB); maximum allowed is #{limit_mb} MB"
        )
      end
    end
  end
end
