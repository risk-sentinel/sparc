# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/support/tls_test_server").to_s

# #1354 — ExchangeFetcher is the connector's only outbound GET. The decision
# logic (URL, host, address rules) is tested directly; the transport rules
# (pinning, redirects, size, timeouts, proxy CONNECT) run over a REAL TLS
# socket on 127.0.0.1 with an in-test CA, so they prove behaviour, not
# configuration. No spec here touches the internet: every host resolves
# through an injected resolver.
RSpec.describe ExchangeFetcher do
  let(:host) { "trust.sparc.invalid" }
  let(:public_resolver) { ->(_h) { [ "93.184.216.34" ] } }

  def fetcher(**opts)
    described_class.new(allowed_hosts: [ host ], resolver: public_resolver, **opts)
  end

  def error_for
    yield
    raise "expected ExchangeFetcher::Error"
  rescue ExchangeFetcher::Error => e
    e
  end

  describe "construction" do
    it "requires at least one host" do
      expect { described_class.new(allowed_hosts: []) }.to raise_error(ArgumentError, /host/)
    end

    it "accepts at most two key pins, each 64 hex characters" do
      pin = "a" * 64
      expect { fetcher(spki_sha256: [ pin, "b" * 64 ]) }.not_to raise_error
      expect { fetcher(spki_sha256: [ pin, "b" * 64, "c" * 64 ]) }.to raise_error(ArgumentError, /at most 2/)
      expect { fetcher(spki_sha256: [ "nothex" ]) }.to raise_error(ArgumentError, /64 hex/)
    end

    it "rejects an invalid CIDR and a Host header override" do
      expect { fetcher(allowed_cidrs: [ "not-a-cidr" ]) }.to raise_error(ArgumentError, /CIDR/)
      expect { fetcher(headers: { "host" => "evil" }) }.to raise_error(ArgumentError, /Host/)
    end

    it "never shows a credential header value in inspect" do
      f = fetcher(headers: { "Authorization" => "Bearer s3cret-token" })
      expect(f.inspect).not_to include("s3cret-token")
      expect(f.inspect).to include("Authorization")
    end
  end

  describe "rule 1: HTTPS only, no userinfo" do
    it "refuses http, ftp and file URLs" do
      %w[http://trust.sparc.invalid/a ftp://trust.sparc.invalid/a file:///etc/passwd].each do |url|
        expect(error_for { fetcher.check_url!(url) }.reason).to eq(:scheme)
      end
    end

    it "refuses a URL carrying a user name or password, without echoing it" do
      err = error_for { fetcher.check_url!("https://user:pw-secret@trust.sparc.invalid/a") }
      expect(err.reason).to eq(:scheme)
      expect(err.message).not_to include("pw-secret")
    end

    it "refuses an unparseable URL" do
      expect(error_for { fetcher.check_url!("https://exa mple/") }.reason).to eq(:scheme)
    end

    it "accepts an https URL on any port" do
      expect(fetcher.check_url!("https://trust.sparc.invalid:8443/x").port).to eq(8443)
    end
  end

  describe "rule 2: exact host pin" do
    it "matches case-insensitively and ignores a trailing dot" do
      expect { fetcher.check_url!("https://TRUST.Sparc.Invalid./doc.json") }.not_to raise_error
    end

    it "refuses a subdomain, a parent domain, and a look-alike" do
      %w[https://evil.trust.sparc.invalid/ https://sparc.invalid/ https://trust.sparc.invalid.evil.com/].each do |url|
        expect(error_for { fetcher.check_url!(url) }.reason).to eq(:host_not_allowed)
      end
    end
  end

  describe "address classification" do
    {
      "127.0.0.1" => "loopback", "127.8.9.10" => "loopback", "::1" => "loopback",
      "10.1.2.3" => "private", "172.16.0.1" => "private", "172.31.255.255" => "private", "192.168.1.1" => "private",
      "fd00::1" => "private (unique local)", "fc00::1" => "private (unique local)",
      "169.254.169.254" => "link-local (cloud metadata)", "fe80::1" => "link-local",
      "0.0.0.0" => "unspecified", "::" => "unspecified",
      "224.0.0.1" => "multicast", "ff02::1" => "multicast",
      "100.64.0.1" => "carrier-grade NAT", "100.127.255.254" => "carrier-grade NAT",
      "240.0.0.1" => "reserved", "255.255.255.255" => "reserved",
      "::ffff:127.0.0.1" => "loopback, embedded in IPv6",
      "::ffff:169.254.169.254" => "link-local (cloud metadata), embedded in IPv6",
      "::ffff:10.0.0.1" => "private, embedded in IPv6",
      "64:ff9b::a9fe:a9fe" => "link-local (cloud metadata), embedded in IPv6",
      "2002:7f00:0001::1" => "loopback, embedded in IPv6",
      "::127.0.0.1" => "loopback, embedded in IPv6"
    }.each do |ip, label|
      it "blocks #{ip} as #{label}" do
        expect(described_class.blocked_label(ip)).to eq(label)
      end
    end

    %w[93.184.216.34 8.8.8.8 172.32.0.1 100.128.0.1 2606:4700::1111 ::ffff:8.8.8.8].each do |ip|
      it "allows public #{ip}" do
        expect(described_class.blocked_label(ip)).to be_nil
      end
    end
  end

  describe "rule 3: DNS resolved once, every address vetted" do
    it "refuses when ANY resolved address is internal" do
      f = described_class.new(allowed_hosts: [ host ], resolver: ->(_) { [ "93.184.216.34", "10.0.0.5" ] })
      err = error_for { f.vet_addresses!(host) }
      expect(err.reason).to eq(:blocked_address)
      expect(err.message).to include("10.0.0.5", "private")
    end

    it "refuses the cloud metadata address" do
      f = described_class.new(allowed_hosts: [ host ], resolver: ->(_) { [ "169.254.169.254" ] })
      expect(error_for { f.vet_addresses!(host) }.reason).to eq(:blocked_address)
    end

    it "refuses an IP-literal host in a blocked range without consulting DNS" do
      resolver = ->(_) { raise "must not be called" }
      f = described_class.new(allowed_hosts: [ "127.0.0.1" ], resolver: resolver)
      expect(error_for { f.vet_addresses!("127.0.0.1") }.reason).to eq(:blocked_address)
    end

    it "allows a blocked range only inside allowed_cidrs" do
      f = described_class.new(allowed_hosts: [ host ], allowed_cidrs: [ "10.0.0.0/24" ], resolver: ->(_) { [ "10.0.0.5" ] })
      expect(f.vet_addresses!(host)).to eq("10.0.0.5")
    end

    it "with allowed_cidrs, refuses a public address outside them" do
      f = described_class.new(allowed_hosts: [ host ], allowed_cidrs: [ "203.0.113.0/24" ],
                              resolver: ->(_) { [ "203.0.113.9", "93.184.216.34" ] })
      err = error_for { f.vet_addresses!(host) }
      expect(err.reason).to eq(:blocked_address)
      expect(err.message).to include("outside")
    end

    it "matches an IPv4-mapped address against an IPv4 CIDR" do
      f = described_class.new(allowed_hosts: [ host ], allowed_cidrs: [ "127.0.0.1/32" ], resolver: ->(_) { [ "::ffff:127.0.0.1" ] })
      expect { f.vet_addresses!(host) }.not_to raise_error
    end

    it "reports :dns when the name does not resolve" do
      f = described_class.new(allowed_hosts: [ host ], resolver: ->(_) { raise SocketError, "nodename nor servname" })
      expect(error_for { f.vet_addresses!(host) }.reason).to eq(:dns)
      f = described_class.new(allowed_hosts: [ host ], resolver: ->(_) { [] })
      expect(error_for { f.vet_addresses!(host) }.reason).to eq(:dns)
    end

    it "#get refuses before any socket is opened" do
      f = described_class.new(allowed_hosts: [ host ], resolver: ->(_) { [ "127.0.0.1" ] })
      expect(Net::HTTP).not_to receive(:new)
      expect(error_for { f.get("https://#{host}/doc.json") }.reason).to eq(:blocked_address)
    end
  end

  describe "SPKI pin value" do
    it "is the SHA-256 of the SubjectPublicKeyInfo DER" do
      leaf, key = TlsTestServer.trusted_ca.issue
      expect(described_class.spki_sha256_of(leaf)).to eq(Digest::SHA256.hexdigest(key.public_to_der))
    end
  end

  # ---- over a real TLS socket ------------------------------------------------

  # A tiny HTTPS server on 127.0.0.1, presenting a leaf from TlsTestServer's
  # in-test CA (#783). Routes by path; each route is ->(io, port). It records
  # each request head so a spec can prove what the client did (or did NOT)
  # send. Helpers are methods, not constants: a constant here would be global.
  def http_reply(io, status, body, type)
    io.write("HTTP/1.1 #{status}\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
  end

  def default_routes
    {
      "/doc.json" => ->(io, _) { http_reply(io, "200 OK", '{"ok":true}', "application/json") },
      "/redirect" => lambda { |io, _|
        io.write("HTTP/1.1 302 Found\r\nLocation: https://elsewhere.test/x?token=abc\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
      },
      "/missing" => ->(io, _) { http_reply(io, "404 Not Found", "nope", "text/plain") },
      "/declared-big" => ->(io, _) { http_reply(io, "200 OK", "x" * 2048, "application/json") },
      "/streamed-big" => lambda { |io, _|
        io.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n")
        20.times { io.write("y" * 1024) }
      },
      "/slow" => lambda { |io, _|
        sleep 2
        http_reply(io, "200 OK", "{}", "application/json")
      }
    }
  end

  def start_trust_center(sans:, routes: {})
    leaf, key = TlsTestServer.trusted_ca.issue(common_name: "trust", sans: sans)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert = leaf
    ctx.key = key
    table = default_routes.merge(routes)
    requests = Queue.new
    tcp = TCPServer.new("127.0.0.1", 0)
    port = tcp.addr[1]
    thread = Thread.new do
      loop do
        sock = tcp.accept
        begin
          ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
          ssl.accept
          head = []
          while (line = ssl.gets)
            break if line.strip.empty?

            head << line.strip
          end
          next if head.empty? # the client hung up after the handshake (pin refused)

          requests << head
          route = table[head.first.split[1]] || ->(io, _) { http_reply(io, "404 Not Found", "", "text/plain") }
          route.call(ssl, port)
        rescue StandardError
          nil
        ensure
          sock.close
        end
      end
    rescue IOError, Errno::EBADF
      nil
    end
    stop = lambda do
      tcp.close
      thread.kill
      thread.join(1)
    end
    drain = lambda do
      heads = []
      heads << requests.pop until requests.empty?
      heads
    end
    { port: port, leaf: leaf, stop: stop, requests: drain }
  end

  context "over a real TLS connection to 127.0.0.1" do
    let(:routes) { {} }
    let(:server) { start_trust_center(sans: [ "DNS:#{host}" ], routes: routes) }
    let(:store) { OpenSSL::X509::Store.new.tap { |s| s.add_cert(TlsTestServer.trusted_ca.cert) } }
    let(:local_resolver) { ->(_h) { [ "127.0.0.1" ] } }
    let(:good_pin) { described_class.spki_sha256_of(server[:leaf]) }
    let(:url) { "https://#{host}:#{server[:port]}" }

    def local(**opts)
      described_class.new(allowed_hosts: [ host ], allowed_cidrs: [ "127.0.0.1/32" ], resolver: local_resolver,
                          cert_store: store, open_timeout: 2, read_timeout: 2, **opts)
    end

    around do |example|
      saved = %w[https_proxy HTTPS_PROXY no_proxy NO_PROXY].index_with { |k| ENV[k] }
      saved.each_key { |k| ENV.delete(k) }
      begin
        example.run
      ensure
        saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
        server[:stop].call
      end
    end

    it "refuses 127.0.0.1 when it is not in allowed_cidrs" do
      f = described_class.new(allowed_hosts: [ host ], resolver: local_resolver, cert_store: store)
      expect(error_for { f.get("#{url}/doc.json") }.reason).to eq(:blocked_address)
    end

    it "fetches with a matching pin, connecting to the vetted IP with SNI and Host set to the hostname" do
      result = local(spki_sha256: [ "0" * 64, good_pin ], headers: { "Authorization" => "Bearer t0ken" }).get("#{url}/doc.json")

      expect(result.body).to eq('{"ok":true}')
      expect(result).to have_attributes(status: 200, content_type: "application/json", peer_ip: "127.0.0.1",
                                        spki_sha256: good_pin, bytes: 11, sha256: Digest::SHA256.hexdigest('{"ok":true}'),
                                        final_url: "#{url}/doc.json")
      head = server[:requests].call.first
      expect(head).to include("Host: #{host}:#{server[:port]}", "Authorization: Bearer t0ken", "Accept-Encoding: identity")
    end

    it "fetches with CA trust alone when no pin is set" do
      expect(local.get("#{url}/doc.json").spki_sha256).to eq(good_pin)
    end

    it "refuses a pin mismatch and never sends the request or its credentials" do
      err = error_for { local(spki_sha256: [ "f" * 64 ], headers: { "Authorization" => "Bearer t0ken" }).get("#{url}/doc.json") }
      expect(err.reason).to eq(:pin_mismatch)
      expect(err.message).to include(good_pin)
      expect(err.message).not_to include("t0ken")
      sleep 0.2 # let the server thread finish reading the (empty) head
      expect(server[:requests].call).to be_empty
    end

    it "refuses a certificate from a CA it does not trust" do
      err = error_for { local(cert_store: OpenSSL::X509::Store.new).get("#{url}/doc.json") }
      expect(err.reason).to eq(:tls)
    end

    it "refuses a trusted certificate issued for another host name" do
      other = "other.sparc.invalid"
      f = described_class.new(allowed_hosts: [ other ], allowed_cidrs: [ "127.0.0.1/32" ], resolver: local_resolver,
                              cert_store: store, open_timeout: 2, read_timeout: 2)
      expect(error_for { f.get("https://#{other}:#{server[:port]}/doc.json") }.reason).to eq(:tls)
    end

    it "does not follow a redirect and names its Location without the query" do
      err = error_for { local.get("#{url}/redirect") }
      expect(err).to have_attributes(reason: :redirect, status: 302)
      expect(err.message).to include("https://elsewhere.test/x")
      expect(err.message).not_to include("token=abc")
      expect(server[:requests].call.size).to eq(1)
    end

    it "reports a non-2xx status" do
      expect(error_for { local.get("#{url}/missing") }).to have_attributes(reason: :status, status: 404)
    end

    it "refuses a declared Content-Length past the cap" do
      expect(error_for { local(max_bytes: 1024).get("#{url}/declared-big") }.reason).to eq(:too_large)
    end

    it "aborts a streamed body (no Content-Length) once it passes the cap" do
      expect(error_for { local(max_bytes: 4096).get("#{url}/streamed-big") }.reason).to eq(:too_large)
    end

    it "times out a server that stops answering" do
      expect(error_for { local(read_timeout: 0.3).get("#{url}/slow") }.reason).to eq(:timeout)
    end

    describe "#discover" do
      let(:index_json) do
        lambda do |port|
          base = "https://#{host}:#{port}"
          {
            "documents" => [
              { "href" => "#{base}/ssp.json" },
              { "nested" => { "u" => "#{base}/package/123" } },
              "#{base}/scan.xml",
              "#{base}/about",                     # not a document path
              "https://evil.test/ssp.json",        # not a pinned host
              "http://#{host}:#{port}/plain.json", # not https
              "#{base}/ssp.json"                   # duplicate
            ]
          }.to_json
        end
      end
      let(:index_html) do
        <<~HTML
          <html><body>
            <a href="/docs/sar.json">SAR</a>
            <a href="poam.xml#top">POA&amp;M</a>
            <a href="#section">skip</a>
            <a href="https://evil.test/x.json">offsite</a>
            <a href="javascript:alert(1)">js</a>
            <a href="/docs/sar.json">dup</a>
          </body></html>
        HTML
      end
      let(:routes) do
        json = index_json
        html = index_html
        {
          "/index.json" => ->(io, port) { http_reply(io, "200 OK", json.call(port), "application/json") },
          "/dir/index.html" => ->(io, _) { http_reply(io, "200 OK", html, "text/html") }
        }
      end

      it "lists document links from a JSON index: pinned hosts, https only, de-duplicated, never pulled" do
        found = local.discover("#{url}/index.json")
        expect(found).to eq([
          { url: "#{url}/ssp.json", hint_format: "json" },
          { url: "#{url}/package/123", hint_format: nil },
          { url: "#{url}/scan.xml", hint_format: "xml" }
        ])
        expect(server[:requests].call.size).to eq(1)
      end

      it "lists <a href> links from an HTML index, resolved against the page URL" do
        found = local.discover("#{url}/dir/index.html")
        expect(found).to eq([
          { url: "#{url}/docs/sar.json", hint_format: "json" },
          { url: "#{url}/dir/poam.xml", hint_format: "xml" }
        ])
      end

      it "caps the list" do
        stub_const("ExchangeFetcher::MAX_DISCOVERED", 1)
        expect(local.discover("#{url}/index.json").size).to eq(1)
      end

      it "applies the same rules to the root URL" do
        expect(error_for { local.discover("https://evil.test/index.json") }.reason).to eq(:host_not_allowed)
      end
    end

    describe "rule 4: through an egress proxy" do
      # A fake proxy on 127.0.0.1 that records the CONNECT line and refuses
      # it, so nothing goes past it. The target resolves to a TEST-NET address
      # (loopback targets are never proxied, as in SparcHttp).
      def through_fake_proxy(resolved)
        proxy = TCPServer.new("127.0.0.1", 0)
        seen = Queue.new
        thread = Thread.new do
          Thread.current.report_on_exception = false
          sock = proxy.accept
          seen << sock.gets.to_s.strip
          sock.write("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
          sock.close
        end
        ENV["https_proxy"] = "http://127.0.0.1:#{proxy.addr[1]}"
        f = described_class.new(allowed_hosts: [ host ], resolver: ->(_) { [ resolved ] }, open_timeout: 2, read_timeout: 2)
        err = error_for { f.get("https://#{host}:8443/doc.json") }
        [ err, seen.empty? ? nil : seen.pop ]
      ensure
        thread&.join(1)
        proxy&.close
      end

      it "sends CONNECT to the vetted IP, not the hostname, so the proxy cannot re-resolve" do
        err, connect_line = through_fake_proxy("192.0.2.10")
        expect(err.reason).to eq(:connection)
        expect(err.message).to include("proxy")
        expect(connect_line).to eq("CONNECT 192.0.2.10:8443 HTTP/1.1")
      end

      it "brackets an IPv6 address in the CONNECT line" do
        _, connect_line = through_fake_proxy("2001:db8::10")
        expect(connect_line).to eq("CONNECT [2001:db8::10]:8443 HTTP/1.1")
      end

      it "honours NO_PROXY for the host" do
        ENV["no_proxy"] = host
        f = described_class.new(allowed_hosts: [ host ], resolver: ->(_) { [ "192.0.2.10" ] })
        ENV["https_proxy"] = "http://127.0.0.1:9"
        expect(f.send(:proxy_for, URI("https://#{host}/x"), "192.0.2.10")).to be_nil
        ENV.delete("no_proxy")
        expect(f.send(:proxy_for, URI("https://#{host}/x"), "192.0.2.10").port).to eq(9)
      end

      it "still vets the address when a proxy applies" do
        ENV["https_proxy"] = "http://127.0.0.1:9"
        f = described_class.new(allowed_hosts: [ host ], resolver: ->(_) { [ "10.0.0.1" ] })
        expect(error_for { f.get("https://#{host}/doc.json") }.reason).to eq(:blocked_address)
      end
    end
  end
end
