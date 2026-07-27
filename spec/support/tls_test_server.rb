# frozen_string_literal: true

require "openssl"
require "socket"
require "tempfile"
require "net/ldap"

# Real-handshake TLS test infrastructure for the both-directions verification
# specs (#783).
#
# Why this exists: a spec that asserts `verify_mode: VERIFY_PEER` was passed to
# Net::HTTP proves only that we *configured* verification. It cannot detect a
# stack that accepts an untrusted certificate anyway — the #773 class of bug.
# These helpers stand up a genuine TLS listener with an in-test CA so a spec can
# assert the *behavior*: an untrusted certificate is REJECTED, a trusted one is
# ACCEPTED, over a real handshake.
#
# Two independent CAs are provided. `trusted_ca` issues the leaf the client is
# told to trust; `rogue_ca` stands in for an on-path attacker presenting a
# well-formed certificate from a CA nobody installed. The only difference
# between the positive and negative cases is which CA signed the leaf — so a
# passing negative test cannot be explained by the server being unreachable.
#
# Key generation is memoized per process: RSA-2048 keygen is the slow part and
# the CAs are fixtures, not subjects.
module TlsTestServer
  KEY_BITS = 2048
  VALIDITY = 3600 # seconds

  # Net::LDAP::AsnSyntax is the CLIENT's decoding table: it knows the response
  # PDUs a client receives, and omits ExtendedRequest (application constructed
  # 23) because a client never reads one. We are the server, so we need it —
  # without it read_ber raises "Unsupported object type: id=119" on StartTLS.
  SERVER_ASN_SYNTAX = Net::BER.compile_syntax(
    application: {
      primitive: { 2 => :null }, # UnbindRequest
      constructed: {
        0 => :array,  # BindRequest
        2 => :array,  # UnbindRequest
        3 => :array,  # SearchRequest
        23 => :array  # ExtendedRequest (StartTLS)
      }
    },
    context_specific: {
      primitive: { 0 => :string, 1 => :string, 2 => :string, 3 => :string, 4 => :string, 7 => :string },
      constructed: { 0 => :array, 1 => :array, 2 => :array, 3 => :array, 4 => :array,
                     5 => :array, 6 => :array, 7 => :array, 9 => :array }
    },
    universal: { constructed: { 107 => :string } }
  )

  # A self-signed CA that can issue leaf certificates.
  class CertificateAuthority
    attr_reader :cert, :key

    def initialize(common_name:)
      @key = OpenSSL::PKey::RSA.new(KEY_BITS)
      @cert = OpenSSL::X509::Certificate.new
      @cert.version = 2
      @cert.serial = 1
      @cert.subject = OpenSSL::X509::Name.parse("/CN=#{common_name}")
      @cert.issuer = @cert.subject
      @cert.public_key = @key.public_key
      @cert.not_before = Time.now - 60
      @cert.not_after = Time.now + VALIDITY

      ef = OpenSSL::X509::ExtensionFactory.new
      ef.subject_certificate = @cert
      ef.issuer_certificate = @cert
      @cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
      @cert.add_extension(ef.create_extension("keyUsage", "keyCertSign,cRLSign", true))
      @cert.add_extension(ef.create_extension("subjectKeyIdentifier", "hash", false))
      @cert.sign(@key, OpenSSL::Digest.new("SHA256"))
    end

    # Issue a server leaf valid for "localhost" / 127.0.0.1 so hostname
    # verification (which Net::HTTP performs on top of chain validation) passes
    # for the trusted case and is not the reason the untrusted case fails.
    def issue(common_name: "localhost", sans: [ "DNS:localhost", "IP:127.0.0.1" ])
      leaf_key = OpenSSL::PKey::RSA.new(KEY_BITS)
      leaf = OpenSSL::X509::Certificate.new
      leaf.version = 2
      leaf.serial = 2
      leaf.subject = OpenSSL::X509::Name.parse("/CN=#{common_name}")
      leaf.issuer = cert.subject
      leaf.public_key = leaf_key.public_key
      leaf.not_before = Time.now - 60
      leaf.not_after = Time.now + VALIDITY

      ef = OpenSSL::X509::ExtensionFactory.new
      ef.subject_certificate = leaf
      ef.issuer_certificate = cert
      leaf.add_extension(ef.create_extension("basicConstraints", "CA:FALSE", true))
      leaf.add_extension(ef.create_extension("keyUsage", "digitalSignature,keyEncipherment", true))
      leaf.add_extension(ef.create_extension("extendedKeyUsage", "serverAuth", false))
      leaf.add_extension(ef.create_extension("subjectAltName", sans.join(","), false))
      leaf.sign(key, OpenSSL::Digest.new("SHA256"))

      [ leaf, leaf_key ]
    end

    # PEM of the CA certificate, written to a tempfile whose path can be handed
    # to `ca_file:` or SSL_CERT_FILE. Memoized so the path is stable.
    def ca_file
      @ca_file ||= begin
        file = Tempfile.new([ "sparc-test-ca", ".pem" ])
        file.write(cert.to_pem)
        file.flush
        # Hold the handle for the life of the process so the file is not reaped.
        @ca_file_handle = file
        file.path
      end
    end
  end

  class << self
    def trusted_ca
      @trusted_ca ||= CertificateAuthority.new(common_name: "SPARC Test Trusted CA")
    end

    # A perfectly valid CA that the client has NOT been told to trust — the
    # stand-in for an on-path interceptor.
    def rogue_ca
      @rogue_ca ||= CertificateAuthority.new(common_name: "SPARC Test Rogue CA")
    end

    # Start an HTTPS listener presenting `ca`'s leaf, yield the base URI, and
    # always shut down. Speaks just enough HTTP/1.1 to answer a GET.
    #
    # NOTE: WEBrick is not a default gem in Ruby 3.4, so this is a raw
    # OpenSSL::SSL::SSLSocket over TCPServer rather than an HTTPS toy server —
    # nothing extra to add to the Gemfile.
    def https(ca: trusted_ca, body: '{"ok":true}', status: "200 OK", sans: nil, &example)
      handler = ->(sock, ctx) { handle_http(upgrade(sock, ctx), body: body, status: status) }
      serve(ca: ca, handler: handler, sans: sans, &example)
    end

    # Start an LDAPS listener presenting `ca`'s leaf and answering bind + search
    # well enough for LdapAuthService to complete a full authenticate() flow.
    #
    # `starttls: true` serves LDAP in the clear until the client sends the
    # StartTLS extendedRequest (OID 1.3.6.1.4.1.1466.20037), then upgrades —
    # so the start_tls code path is genuinely exercised rather than failing for
    # protocol reasons against an implicit-TLS listener.
    def ldaps(ca: trusted_ca, entry_dn: "uid=jdoe,ou=people,dc=example,dc=com",
              attributes: {}, starttls: false, sans: nil, &example)
      attrs = { "uid" => [ "jdoe" ], "mail" => [ "jdoe@example.com" ], "cn" => [ "J Doe" ] }.merge(attributes)
      handler = lambda do |sock, ctx|
        sock = starttls ? negotiate_starttls(sock, ctx) : upgrade(sock, ctx)
        handle_ldap(sock, entry_dn: entry_dn, attributes: attrs) if sock
      end
      serve(ca: ca, handler: handler, sans: sans, &example)
    end

    private

    # Shared plumbing: bind an ephemeral port, run `handler` for each accepted
    # connection on a background thread, and yield {host:, port:, uri:, ca_file:}
    # to the example. The handler decides WHEN to start TLS (immediately, or
    # after a StartTLS negotiation), so both models share this loop.
    def serve(ca:, handler:, sans: nil)
      leaf, leaf_key = sans ? ca.issue(sans: sans) : ca.issue

      ctx = OpenSSL::SSL::SSLContext.new
      ctx.cert = leaf
      ctx.key = leaf_key

      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]

      thread = Thread.new do
        loop do
          socket = begin
            server.accept
          rescue IOError, Errno::EBADF
            break # listener closed by the ensure below
          end

          begin
            handler.call(socket, ctx)
          rescue StandardError => e
            # Expected in the negative case: the client rejected our chain and
            # tore the connection down mid-handshake. Keep serving. Set
            # TLS_TEST_DEBUG=1 to surface handler errors while writing specs.
            warn("[tls-test-server] #{e.class}: #{e.message}") if ENV["TLS_TEST_DEBUG"]
          ensure
            begin
              socket.close
            rescue StandardError
              nil
            end
          end
        end
      end

      begin
        yield({
          host: "localhost",
          port: port,
          uri: URI("https://localhost:#{port}/"),
          ca_file: ca.ca_file
        })
      ensure
        begin
          server.close
        rescue StandardError
          nil
        end
        thread&.kill
        thread&.join(1)
      end
    end

    # Wrap an accepted TCP socket in TLS and complete the handshake.
    def upgrade(socket, ctx)
      ssl = OpenSSL::SSL::SSLSocket.new(socket, ctx)
      ssl.sync_close = false
      ssl.accept
      ssl
    end

    # Serve LDAP in the clear until the StartTLS extendedRequest arrives, answer
    # it with success, then upgrade the same socket to TLS.
    STARTTLS_OID = "1.3.6.1.4.1.1466.20037"

    def negotiate_starttls(socket, ctx)
      loop do
        message = socket.read_ber(SERVER_ASN_SYNTAX)
        return nil if message.nil?

        message_id = message[0]
        request = message[1]
        next unless request.ber_identifier == 0x77 # extendedRequest [APPLICATION 23]

        response = [
          0.to_ber_enumerated, # resultCode: success
          "".to_ber,           # matchedDN
          "".to_ber,           # diagnosticMessage
          STARTTLS_OID.to_ber_contextspecific(10) # responseName
        ].to_ber_appsequence(24) # extendedResponse [APPLICATION 24]
        socket.write(ldap_message(message_id, response))

        return upgrade(socket, ctx)
      end
    end

    def handle_http(ssl, body:, status:)
      # Drain the request head so the client is not writing into a closed pipe.
      while (line = ssl.gets)
        break if line.strip.empty?
      end
      ssl.write(
        "HTTP/1.1 #{status}\r\n" \
        "Content-Type: application/json\r\n" \
        "Content-Length: #{body.bytesize}\r\n" \
        "Connection: close\r\n\r\n#{body}"
      )
    end

    def handle_ldap(ssl, entry_dn:, attributes:)
      loop do
        message = ssl.read_ber(SERVER_ASN_SYNTAX)
        break if message.nil?

        message_id = message[0]
        request = message[1]

        case request.ber_identifier
        when 0x60 # bindRequest [APPLICATION 0]
          ssl.write(ldap_message(message_id, ldap_result(1)))
        when 0x63 # searchRequest [APPLICATION 3]
          ssl.write(ldap_message(message_id, ldap_entry(entry_dn, attributes)))
          ssl.write(ldap_message(message_id, ldap_result(5)))
        when 0x42 # unbindRequest
          break
        else
          break
        end
      end
    end

    # LDAPResult (success) wrapped in the given APPLICATION tag.
    def ldap_result(app_tag)
      [
        0.to_ber_enumerated, # resultCode: success
        "".to_ber,           # matchedDN
        "".to_ber            # diagnosticMessage
      ].to_ber_appsequence(app_tag)
    end

    def ldap_entry(dn, attributes)
      attrs = attributes.map do |name, values|
        [ name.to_ber, values.map(&:to_ber).to_ber_set ].to_ber_sequence
      end
      [ dn.to_ber, attrs.to_ber_sequence ].to_ber_appsequence(4)
    end

    def ldap_message(message_id, protocol_op)
      [ message_id.to_ber, protocol_op ].to_ber_sequence
    end
  end
end
