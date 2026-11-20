# frozen_string_literal: true

require "net/http"
require "openssl"
require "ipaddr"
require "socket"
require "digest"
require "json"
require "uri"

# #1354 — the one outbound GET a connector makes to a provider's trust center.
#
# A connection names URLs on someone else's system, so this is the place an
# admin-supplied URL turns into a socket. It must never become a way to reach
# SPARC's own network, the cloud metadata service, or a host nobody pinned
# (server-side request forgery). Every rule below is checked before a single
# byte of a credential leaves SPARC.
#
#   1. HTTPS only, and no `user:pass@` in the URL.                    (SC-8, SI-10)
#   2. The host must be one of the connection's pinned hosts.         (SC-7, CA-3)
#   3. DNS is resolved ONCE here. If ANY address is loopback, private,
#      link-local (incl. 169.254.169.254 metadata), unspecified, multicast,
#      CGNAT, reserved, or an IPv6 form that embeds one of those, the fetch
#      is refused, unless the address is inside the connection's own CIDR
#      list. When a CIDR list is set, EVERY address must be inside it.
#      The socket then connects to that vetted IP (Net::HTTP#ipaddr=) with
#      SNI, certificate hostname check and Host header still the hostname,
#      so a DNS answer that changes between the check and the connect
#      (rebinding) can't move the connection.                         (SC-7)
#   4. Egress proxy (#775, SparcHttp): the same scheme-strict,
#      NO_PROXY-aware rule SparcHttp uses decides whether a proxy applies.
#      Through a proxy the CONNECT line names the vetted IP, not the
#      hostname, so the proxy is told exactly where to go and can't
#      re-resolve. The checks are never skipped because a proxy applies:
#      if SPARC can't resolve the host itself (a proxy-only DNS network),
#      the fetch fails with :dns rather than trusting the proxy's answer.
#      A TLS-inspecting proxy presents its own certificate, so it works
#      only without key pins (its CA must be trusted via SSL_CERT_FILE,
#      #774); with pins it is refused as :pin_mismatch.
#   5. TLS is VERIFY_PEER against the system / SSL_CERT_FILE store, as every
#      SPARC client does. With key pins, the SHA-256 of the leaf
#      certificate's SubjectPublicKeyInfo must match one pin, checked after
#      the handshake and BEFORE the request (and its credential headers) is
#      written.                                                        (IA-9, SC-8)
#   6. Redirects are never followed; any 3xx is an error naming the Location.
#   7. The body is streamed and abandoned past max_bytes; open, read and
#      overall time are capped.                                        (SI-10)
#   8. Credential headers are sent, never logged, never echoed in errors.
#
# Plain Ruby, no database: the connection record (PR 2's model) passes its
# pins in; this class only enforces them.
#
# NIST SP 800-53 Rev 5: SC-7 (boundary protection), SC-8 (transmission
# confidentiality and integrity), IA-9 (service identification and
# authentication: host + key pinning), SI-10 (input validation), SA-9
# (external system services), CA-3 (information exchange).
class ExchangeFetcher
  # One error type; `reason` is a stable symbol a caller can store on the
  # connection's last error. The message is safe to show an admin: it never
  # contains a request header value.
  class Error < StandardError
    REASONS = %i[
      scheme host_not_allowed blocked_address dns tls pin_mismatch
      redirect status too_large timeout connection
    ].freeze

    attr_reader :reason, :status

    def initialize(reason, message, status: nil)
      raise ArgumentError, "unknown reason #{reason.inspect}" unless REASONS.include?(reason)

      @reason = reason
      @status = status
      super(message)
    end
  end

  Result = Data.define(:body, :content_type, :final_url, :peer_ip, :spki_sha256, :status, :bytes, :sha256)

  # Addresses refused unless inside the connection's allowed_cidrs. SC-7.
  # Order matters only for the label reported in the error.
  BLOCKED_RANGES = [
    [ "0.0.0.0/8",          "unspecified" ],
    [ "127.0.0.0/8",        "loopback" ],
    [ "10.0.0.0/8",         "private" ],
    [ "172.16.0.0/12",      "private" ],
    [ "192.168.0.0/16",     "private" ],
    [ "100.64.0.0/10",      "carrier-grade NAT" ],
    [ "169.254.0.0/16",     "link-local (cloud metadata)" ],
    [ "192.0.0.0/24",       "IETF protocol assignments" ],
    [ "198.18.0.0/15",      "benchmarking" ],
    [ "224.0.0.0/4",        "multicast" ],
    [ "240.0.0.0/4",        "reserved" ],
    [ "::/128",             "unspecified" ],
    [ "::1/128",            "loopback" ],
    [ "fc00::/7",           "private (unique local)" ],
    [ "fe80::/10",          "link-local" ],
    [ "fec0::/10",          "site-local" ],
    [ "ff00::/8",           "multicast" ],
    [ "64:ff9b:1::/48",     "local-use NAT64" ],
    [ "2001::/32",          "Teredo" ],
    [ "100::/64",           "discard-only" ]
  ].map { |cidr, label| [ IPAddr.new(cidr), label ] }.freeze

  # IPv6 forms that carry an IPv4 address; the embedded address is classified
  # as if it were the destination (::ffff:127.0.0.1 is loopback).
  NAT64_WKP = IPAddr.new("64:ff9b::/96")
  SIX_TO_FOUR = IPAddr.new("2002::/16")
  IPV4_COMPAT = IPAddr.new("::/96")

  HEX_PIN = /\A[0-9a-f]{64}\z/
  MAX_PINS = 2
  MAX_DISCOVERED = 500
  DEFAULT_OPEN_TIMEOUT = 10
  DEFAULT_READ_TIMEOUT = 30
  DEFAULT_MAX_DURATION = 120
  RESOLVE_TIMEOUT = 10

  attr_reader :allowed_hosts, :spki_sha256, :allowed_cidrs, :max_bytes

  # allowed_hosts: exact host names (case-insensitive) a URL may name.
  # spki_sha256:   0–2 hex SHA-256 pins of the server key; empty = CA trust only.
  # allowed_cidrs: optional ranges; when set every resolved address must be in one,
  #                and they are the only way to reach a range in BLOCKED_RANGES.
  # headers:       credential headers for the request; never logged.
  # resolver:      ->(host) { [ip strings] }, injectable for specs.
  # cert_store:    OpenSSL::X509::Store; nil = the system / SSL_CERT_FILE store.
  def initialize(allowed_hosts:, spki_sha256: [], allowed_cidrs: [], max_bytes: SparcConfig.max_upload_bytes,
                 open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
                 max_duration: DEFAULT_MAX_DURATION, headers: {}, resolver: nil, cert_store: nil)
    @allowed_hosts = Array(allowed_hosts).map { |h| self.class.normalize_host(h) }.compact_blank.uniq
    raise ArgumentError, "at least one allowed host is required" if @allowed_hosts.empty?

    @spki_sha256 = Array(spki_sha256).map { |p| p.to_s.strip.downcase.delete(":") }.compact_blank.uniq
    raise ArgumentError, "at most #{MAX_PINS} key pins" if @spki_sha256.size > MAX_PINS
    raise ArgumentError, "a key pin must be 64 hex characters (SHA-256)" unless @spki_sha256.all? { |p| p.match?(HEX_PIN) }

    @allowed_cidrs = Array(allowed_cidrs).compact_blank.map { |c| IPAddr.new(c.to_s.strip) }
    @max_bytes = Integer(max_bytes)
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @max_duration = max_duration
    @headers = headers.to_h.transform_keys(&:to_s)
    raise ArgumentError, "the Host header is set from the URL" if @headers.keys.any? { |k| k.casecmp?("host") }

    @resolver = resolver || method(:system_resolve)
    @cert_store = cert_store
  rescue IPAddr::InvalidAddressError => e
    raise ArgumentError, "invalid CIDR: #{e.message}"
  end

  # Masks the header values so an accidental `inspect` (a log line, an error
  # report) never prints a credential.
  def inspect
    "#<#{self.class.name} hosts=#{@allowed_hosts.inspect} pins=#{@spki_sha256.size} " \
      "cidrs=#{@allowed_cidrs.map { |c| "#{c}/#{c.prefix}" }.inspect} headers=#{@headers.keys.inspect}>"
  end
  alias_method :to_s, :inspect

  # Fetch one document. Returns a Result or raises ExchangeFetcher::Error.
  def get(url)
    uri = check_url!(url)
    ip = vet_addresses!(uri.hostname)
    perform(uri, ip)
  end

  # Fetch the root trust-center document (same rules as #get) and LIST the
  # document links in it. Never fetches a candidate: the owner's rule is that
  # only documents explicitly set on a connection are pulled (#1354, decision 3).
  # Returns [{ url:, hint_format: }] (hint_format "json", "xml" or nil).
  def discover(root_url)
    result = get(root_url)
    base = URI(result.final_url)
    links = json_body?(result) ? json_links(result.body) : html_links(result.body, base)
    links.filter_map { |link| candidate(link, base) }
         .uniq { |c| c[:url] }
         .first(MAX_DISCOVERED)
  end

  # --- rules, public so the decision logic is testable without a socket ---

  def self.normalize_host(host)
    host.to_s.strip.downcase.delete_suffix(".").presence
  end

  # Rule 1 + 2. Returns the parsed URI.
  def check_url!(url)
    uri = URI.parse(url.to_s.strip)
    raise Error.new(:scheme, "Only https:// URLs can be fetched.") unless uri.is_a?(URI::HTTPS)
    raise Error.new(:scheme, "A URL may not carry a user name or password.") if uri.userinfo
    host = self.class.normalize_host(uri.hostname)
    raise Error.new(:scheme, "The URL has no host.") if host.nil?
    unless @allowed_hosts.include?(host)
      raise Error.new(:host_not_allowed, "Host #{host} is not one of this connection's pinned hosts.")
    end

    uri
  rescue URI::Error
    raise Error.new(:scheme, "The URL could not be parsed.")
  end

  # Rule 3. Resolves once and returns the address to connect to.
  def vet_addresses!(host)
    addresses = resolve(host)
    raise Error.new(:dns, "#{host} did not resolve to any address.") if addresses.empty?

    addresses.each do |ip|
      if @allowed_cidrs.any?
        next if @allowed_cidrs.any? { |cidr| cidr_include?(cidr, ip) }

        raise Error.new(:blocked_address, "#{host} resolved to #{ip}, which is outside this connection's IP ranges.")
      end

      label = self.class.blocked_label(ip)
      raise Error.new(:blocked_address, "#{host} resolved to #{ip} (#{label}); add it to the connection's IP ranges to allow it.") if label
    end
    addresses.first.to_s
  end

  # nil when the address is public; otherwise what kind of address it is.
  def self.blocked_label(ip)
    ip = IPAddr.new(ip.to_s) unless ip.is_a?(IPAddr)
    embedded = embedded_ipv4(ip)
    return blocked_label(embedded)&.then { |l| "#{l}, embedded in IPv6" } if embedded

    BLOCKED_RANGES.each do |range, label|
      return label if range.family == ip.family && range.include?(ip)
    end
    nil
  end

  def self.embedded_ipv4(ip)
    return nil unless ip.ipv6?
    return ip.native if ip.ipv4_mapped?

    value = ip.to_i
    if NAT64_WKP.include?(ip) || (IPV4_COMPAT.include?(ip) && value > 1)
      IPAddr.new(value & 0xffff_ffff, Socket::AF_INET)
    elsif SIX_TO_FOUR.include?(ip)
      IPAddr.new((value >> 80) & 0xffff_ffff, Socket::AF_INET)
    end
  end

  # Rule 5: the pin is the SHA-256 of the leaf key's SubjectPublicKeyInfo DER,
  # the same value `openssl x509 -pubkey | openssl pkey -pubin -outform der |
  # sha256sum` prints.
  def self.spki_sha256_of(cert)
    Digest::SHA256.hexdigest(cert.public_key.public_to_der)
  end

  private

  def resolve(host)
    literal = begin
      IPAddr.new(host)
    rescue IPAddr::InvalidAddressError
      nil
    end
    return [ literal ] if literal

    Array(@resolver.call(host)).map { |a| IPAddr.new(a.to_s) }.uniq
  rescue IPAddr::InvalidAddressError, SocketError, Resolv::ResolvError, IO::TimeoutError, Timeout::Error => e
    raise Error.new(:dns, "#{host} could not be resolved (#{e.class.name.demodulize}).")
  end

  def system_resolve(host)
    Addrinfo.getaddrinfo(host, 443, nil, :STREAM, timeout: RESOLVE_TIMEOUT).map(&:ip_address)
  end

  def cidr_include?(cidr, ip)
    candidate = ip.ipv4_mapped? ? ip.native : ip
    cidr.family == candidate.family && cidr.include?(candidate)
  end

  def perform(uri, ip)
    deadline = monotonic + @max_duration
    http = build_http(uri, ip)
    result = nil
    http.start do |conn|
      peer_pin = check_pin!(conn.peer_cert)
      conn.request(build_request(uri)) do |response|
        result = read_response(uri, ip, peer_pin, response, deadline)
      end
    end
    result
  rescue Error
    raise
  rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, IO::TimeoutError, Timeout::Error
    raise Error.new(:timeout, "#{uri.hostname} did not answer in time.")
  rescue OpenSSL::SSL::SSLError => e
    raise Error.new(:tls, "TLS with #{uri.hostname} failed: #{e.message}")
  rescue Net::HTTPClientException, Net::HTTPFatalError, Net::HTTPRetriableError => e
    # Only the proxy's answer to CONNECT reaches here (the target's own
    # response is read in read_response).
    raise Error.new(:connection, "The egress proxy refused the tunnel to #{uri.hostname} (#{e.message}).")
  rescue SystemCallError, SocketError, IOError, EOFError, Net::ProtocolError => e
    raise Error.new(:connection, "Could not reach #{uri.hostname} (#{e.class.name.demodulize}).")
  end

  # SparcHttp's rule (#775) — URI#find_proxy: https_proxy / HTTPS_PROXY only,
  # NO_PROXY honoured, loopback never proxied — evaluated against the address
  # vetted above. find_proxy itself would resolve the host a second time.
  def proxy_for(uri, ip)
    proxy = ENV["https_proxy"].presence || ENV["HTTPS_PROXY"].presence
    return nil if proxy.nil?
    return nil if ip.start_with?("127.") || ip == "::1"

    no_proxy = ENV["no_proxy"] || ENV["NO_PROXY"]
    return nil if no_proxy && !URI::Generic.use_proxy?(uri.hostname, ip, uri.port, no_proxy)

    URI.parse(proxy)
  end

  def build_http(uri, ip)
    proxy = proxy_for(uri, ip)
    http =
      if proxy
        Net::HTTP.new(uri.hostname, uri.port, proxy.hostname, proxy.port, proxy.user, proxy.password)
      else
        Net::HTTP.new(uri.hostname, uri.port, nil, nil, nil, nil)
      end
    # CONNECT writes "#{ipaddr}:#{port}", so an IPv6 address needs brackets there.
    http.ipaddr = proxy && ip.include?(":") ? "[#{ip}]" : ip
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.verify_hostname = true
    http.cert_store = @cert_store if @cert_store
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout
    http.write_timeout = @read_timeout
    http.ssl_timeout = @open_timeout
    http.keep_alive_timeout = 0
    http
  end

  def build_request(uri)
    request = Net::HTTP::Get.new(uri)
    # Exact bytes: the SHA-256 is of what the provider published, and no
    # decompression can inflate past the size cap.
    request["Accept-Encoding"] = "identity"
    request["Accept"] = "application/json, application/xml, text/xml, text/html;q=0.5, */*;q=0.1"
    @headers.each { |k, v| request[k] = v }
    request
  end

  def check_pin!(cert)
    raise Error.new(:tls, "The server presented no certificate.") if cert.nil?

    actual = self.class.spki_sha256_of(cert)
    return actual if @spki_sha256.empty? || @spki_sha256.include?(actual)

    raise Error.new(:pin_mismatch, "The server's key (SHA-256 #{actual}) matches none of this connection's key pins.")
  end

  def read_response(uri, ip, pin, response, deadline)
    code = response.code.to_i
    if response.is_a?(Net::HTTPRedirection)
      raise Error.new(:redirect, "#{uri.hostname} answered #{code}, a redirect to #{safe_location(response['location'])}; " \
                                 "redirects are not followed. Register the target URL instead.", status: code)
    end
    unless response.is_a?(Net::HTTPSuccess)
      raise Error.new(:status, "#{uri.hostname} answered HTTP #{code}.", status: code)
    end

    declared = response["content-length"]&.to_i
    raise too_large(uri) if declared && declared > @max_bytes

    body = read_capped(response, deadline, uri)
    Result.new(body: body, content_type: response["content-type"]&.split(";")&.first&.strip&.downcase,
               final_url: uri.to_s, peer_ip: ip, spki_sha256: pin, status: code,
               bytes: body.bytesize, sha256: Digest::SHA256.hexdigest(body))
  end

  # Rule 7: stop reading the moment the cap or the overall time is passed.
  def read_capped(response, deadline, uri)
    body = String.new(capacity: 16 * 1024, encoding: Encoding::BINARY)
    response.read_body do |chunk|
      body << chunk
      raise too_large(uri) if body.bytesize > @max_bytes
      raise Error.new(:timeout, "#{uri.hostname} took longer than #{@max_duration}s to send the document.") if monotonic > deadline
    end
    body
  end

  def too_large(uri)
    Error.new(:too_large, "The document at #{uri.hostname} is larger than the #{@max_bytes}-byte limit.")
  end

  # The Location is the provider's, but trim its query (it can carry a token)
  # and length before showing it.
  def safe_location(location)
    return "(no Location header)" if location.blank?

    loc = URI.parse(location.to_s)
    loc.query = nil
    loc.userinfo = nil if loc.respond_to?(:userinfo=) && loc.userinfo
    loc.to_s.truncate(200)
  rescue URI::Error
    "(unparseable Location header)"
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # --- discovery ---

  def json_body?(result)
    result.content_type.to_s.include?("json") || result.body.lstrip.start_with?("{", "[")
  end

  def json_links(body)
    strings = []
    walk = lambda do |node|
      case node
      when Hash then node.each_value(&walk)
      when Array then node.each(&walk)
      when String then strings << node if node.start_with?("https://")
      end
    end
    walk.call(JSON.parse(body))
    strings.select { |s| document_path?(s) }
  rescue JSON::ParserError
    []
  end

  def document_path?(url)
    path = URI.parse(url).path.to_s.downcase
    path.end_with?(".json", ".xml") || path.include?("/package/") || path.include?("/packages/")
  rescue URI::Error
    false
  end

  def html_links(body, base)
    Nokogiri::HTML(body).css("a[href]").filter_map do |a|
      href = a["href"].to_s.strip
      next if href.empty? || href.start_with?("#")

      URI.join(base, href).to_s
    rescue URI::Error, ArgumentError
      nil
    end
  end

  def candidate(link, base)
    uri = URI.parse(link)
    return nil unless uri.is_a?(URI::HTTPS) && uri.userinfo.nil?
    return nil unless @allowed_hosts.include?(self.class.normalize_host(uri.hostname))

    uri.fragment = nil
    return nil if uri.to_s == base.to_s

    { url: uri.to_s, hint_format: hint_format(uri.path) }
  rescue URI::Error
    nil
  end

  def hint_format(path)
    case File.extname(path.to_s).downcase
    when ".json" then "json"
    when ".xml" then "xml"
    end
  end
end
