# #904 — carry over the reference implementation's two hardcoded constants so
# coverage analysis behaves on day one exactly as the CLI did.
#
# Source: sparc-iac `oscal/scripts/state_cdef_coverage.py` (sparc-iac#287).
#
# ALWAYS_KEEP entries name a service key with no CDEF requirement from
# Terraform: nginx is a container sidecar and the pipeline is CI/CD, so neither
# ever appears in state. Without these rows both are false-flagged stale on
# every single run.
#
# The CUSTOM_ALIAS entries are NOT seeded blind. Each maps a specific CDEF
# document to a service key, and a document that does not exist in this instance
# cannot be asserted about — so each is created only when a CDEF whose name
# matches is present. Seeding an alias for an absent document would be an
# assertion nobody made.

ALWAYS_KEEP_SERVICE_KEYS = %w[nginx pipeline].freeze

ALWAYS_KEEP_SERVICE_KEYS.each do |key|
  record = CdefServiceAlias.find_or_initialize_by(service_key: key, cdef_document_id: nil)
  record.always_keep = true
  record.note ||= "Not deployed via Terraform; expected to be absent from state (#904)."
  record.save!
end

puts "  ✓ #{ALWAYS_KEEP_SERVICE_KEYS.size} always-keep service aliases"
