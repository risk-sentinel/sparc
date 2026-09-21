# The federation's identity constants, served so peers read them rather than
# embed them (#1155).
#
# Object identity across the federation is UUIDv5 derived from natural keys
# against one namespace UUID. Two properties depend on every peer using the
# SAME namespace: reruns are idempotent, and peers deduplicate without
# coordinating. The second fails silently the moment two peers disagree — the
# same logical object arrives under a second identity and nothing reconciles
# them, which is the failure #1159 describes.
#
# #1155 asked for these to be registered "once, and say where it lives so
# Horizon and any future peer read the same value rather than each embedding a
# constant". This is that place. A peer can still DERIVE the UUID — it is the
# UUIDv5 of the namespace URI, deliberately, so that the value is recomputable
# rather than needing to be told — and this endpoint lets it verify what it
# derived against what SPARC publishes instead of assuming.
#
# Reference data, not tenant data: these values identify the federation, not a
# deployment or a caller, so the response is identical for every authenticated
# caller and carries no permission gate — the same posture as API discovery.
#
# Endpoint:
#   GET /api/v1/federation/identity
#
# NIST 800-53 Controls:
#   IA-2 Identification and Authentication (Bearer token required)
#   AC-3 Access Enforcement (read-only; federation constants are global)
#   SI-10 Information Input Validation (a peer can verify a derived UUID here
#         rather than trusting a copied literal)
#   CA-3 Information Exchange (the agreed identifiers two systems join on)
class Api::V1::FederationIdentitiesController < Api::V1::BaseController
  # GET /api/v1/federation/identity
  def show
    render json: {
      data: {
        namespace_uri: OscalNamespace.uri(:sparc),
        federation_namespace_uuid: OscalNamespace::FEDERATION_NAMESPACE,
        # How the UUID is arrived at, so a peer can reproduce it rather than
        # copy it. Named rather than described: `uuid_v5` over the URL
        # namespace with `namespace_uri` as the name.
        derivation: {
          method: "uuidv5",
          namespace: "url",
          name: OscalNamespace.uri(:sparc)
        }
      },
      meta: {
        # The deployment's OWN vocabulary, which is a different thing and
        # varies per install. Published alongside so an integrator reading one
        # value is not left assuming the other matches it.
        instance_namespace: OscalNamespace.instance,
        api_version: "v1"
      }
    }
  end
end
