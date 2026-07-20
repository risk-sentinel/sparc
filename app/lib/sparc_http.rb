# frozen_string_literal: true

# Centralized outbound HTTP for SPARC (#775).
#
# Ruby's Net::HTTP proxy-from-env default (`p_addr = :ENV`) reads **http_proxy
# only** and ignores **https_proxy**, regardless of request scheme. So the bare
# `Net::HTTP.get(uri)` / `Net::HTTP.start(host, port, ...)` forms scattered across
# the services would silently bypass a mandated egress proxy whenever the
# operator sets the conventional HTTPS_PROXY (and not http_proxy) — every one of
# SPARC's outbound calls is HTTPS.
#
# This helper routes through `URI#find_proxy`, which IS scheme-aware
# (https -> https_proxy, http -> http_proxy, no cross-fallback) and honors
# NO_PROXY. When find_proxy returns nil (no proxy, or host matched by NO_PROXY),
# proxying is explicitly disabled (p_addr = nil) so Net::HTTP does not fall back
# to its http_proxy-only :ENV behavior.
#
# TLS is verified (VERIFY_PEER) for https. Combined with the container custom-CA
# trust (#774), a re-signing MITM egress proxy is fully supported end to end:
# calls route THROUGH it (proxy env) and its re-signed certs are TRUSTED
# (SSL_CERT_FILE / system store).
#
# NIST SC-8 (transmission) / AC-4 (controlled egress via the mandated proxy).
module SparcHttp
  class << self
    # Open a proxy-aware, TLS-verifying Net::HTTP session for `uri` and yield it,
    # mirroring Net::HTTP.start's block form so call sites port with minimal
    # change. Extra keyword opts (open_timeout:, read_timeout:, ...) pass through.
    # Returns the block's value.
    def start(uri, **opts, &block)
      uri = URI(uri.to_s) unless uri.is_a?(URI)
      proxy = uri.find_proxy
      proxy_args =
        if proxy
          [ proxy.hostname, proxy.port, proxy.user, proxy.password ]
        else
          # Explicit no-proxy — do NOT let Net::HTTP fall back to :ENV
          # (http_proxy-only), which is the bug this helper fixes.
          [ nil, nil, nil, nil ]
        end

      start_opts = { use_ssl: uri.scheme == "https" }
      start_opts[:verify_mode] = OpenSSL::SSL::VERIFY_PEER if start_opts[:use_ssl]
      start_opts.merge!(opts)

      Net::HTTP.start(uri.hostname, uri.port, *proxy_args, start_opts, &block)
    end

    # Proxy-aware replacement for Net::HTTP.get(uri): returns the response body
    # as a String. Optional request headers may be supplied.
    def get(uri, headers = {})
      uri = URI(uri.to_s) unless uri.is_a?(URI)
      get_response(uri, headers).body
    end

    # Proxy-aware GET returning the full Net::HTTPResponse (for status/header
    # inspection). Does not follow redirects — matches Net::HTTP.get semantics.
    def get_response(uri, headers = {})
      uri = URI(uri.to_s) unless uri.is_a?(URI)
      request = Net::HTTP::Get.new(uri)
      headers.each { |k, v| request[k] = v }
      start(uri) { |http| http.request(request) }
    end
  end
end
