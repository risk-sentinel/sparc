# frozen_string_literal: true

# #623 — records the user who uploaded a document so async failure paths (the
# stuck-document reaper, the conversion job's rescue) can notify them. The
# association is optional: API/service-account uploads or seed data may have no
# interactive user, and a user deletion nullifies the FK.
module UploadTrackable
  extend ActiveSupport::Concern

  included do
    belongs_to :uploaded_by, class_name: "User",
               foreign_key: "uploaded_by_user_id", optional: true
  end
end
