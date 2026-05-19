# frozen_string_literal: true

# Issue #487 / #492 — Boots the AWS Labs CDEF catalog on first deploy.
#
# The actual decision logic lives in lib/aws_labs_cdef_bootstrap.rb so
# it can be unit-tested directly and so the model layer (CdefDocument)
# is not referenced during initializer evaluation.
#
# Why `to_prepare` instead of `after_initialize`:
#
#   - `after_initialize` fires before eager-loading completes in
#     production. References to ActiveRecord models from inside it can
#     race with autoload ordering and produce
#     "NameError: uninitialized constant ApplicationRecord" (see #492
#     defect 1). `to_prepare` runs after the application is fully
#     loaded and is the documented hook for "things that touch the
#     model layer at boot."
#
#   - In development, `to_prepare` re-runs on every code reload. The
#     module's Rails.cache lock prevents duplicate enqueues within the
#     reload window. In test, the lock check + the SparcConfig flag
#     keep the bootstrap inert by default.
require Rails.root.join("lib/aws_labs_cdef_bootstrap")

Rails.application.config.to_prepare do
  AwsLabsCdefBootstrap.run!
end
