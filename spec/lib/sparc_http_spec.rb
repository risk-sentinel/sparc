# frozen_string_literal: true

require "rails_helper"

# Unit test for SparcHttp (#775). The behavior under test is proxy SELECTION:
# outbound calls must honor https_proxy for https requests (Net::HTTP's :ENV
# default reads http_proxy only) and NO_PROXY, and must NOT fall back to
# http_proxy when no scheme-appropriate proxy is set. We assert the positional
# args the helper passes to Net::HTTP.start rather than opening real sockets.
RSpec.describe SparcHttp do
  # Run the block with the given proxy env vars set, restoring afterwards.
  def with_env(vars)
    keys = %w[http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY]
    saved = keys.to_h { |k| [ k, ENV[k] ] }
    keys.each { |k| ENV.delete(k) }
    vars.each { |k, v| ENV[k.to_s] = v }
    yield
  ensure
    keys.each { |k| ENV.delete(k) }
    saved.each { |k, v| ENV[k] = v unless v.nil? }
  end

  # Capture the args Net::HTTP.start receives for a SparcHttp.start(url) call.
  def start_args_for(url)
    captured = nil
    allow(Net::HTTP).to receive(:start) do |*args, &_blk|
      captured = args
      "result"
    end
    described_class.start(URI(url)) { |h| h }
    # args: [host, port, p_host, p_port, p_user, p_pass, opts]
    {
      host: captured[0], port: captured[1],
      proxy_host: captured[2], proxy_port: captured[3],
      opts: captured.last
    }
  end

  describe "proxy selection" do
    it "routes an https request through https_proxy" do
      with_env(https_proxy: "http://proxy.internal:8080") do
        a = start_args_for("https://api.example.com/x")
        expect(a[:proxy_host]).to eq("proxy.internal")
        expect(a[:proxy_port]).to eq(8080)
      end
    end

    it "does NOT use http_proxy for an https request (scheme-strict)" do
      with_env(http_proxy: "http://proxy.internal:8080") do
        a = start_args_for("https://api.example.com/x")
        # p_host nil => proxy explicitly disabled, not Net::HTTP's :ENV fallback.
        expect(a[:proxy_host]).to be_nil
        expect(a[:proxy_port]).to be_nil
      end
    end

    it "routes an http request through http_proxy" do
      with_env(http_proxy: "http://proxy.internal:8080") do
        a = start_args_for("http://plain.example.com/x")
        expect(a[:proxy_host]).to eq("proxy.internal")
      end
    end

    it "honors NO_PROXY (bypasses the proxy for a matching host)" do
      with_env(https_proxy: "http://proxy.internal:8080", no_proxy: "example.com") do
        a = start_args_for("https://api.example.com/x")
        expect(a[:proxy_host]).to be_nil
      end
    end

    it "disables proxying entirely when no proxy env is set" do
      with_env({}) do
        a = start_args_for("https://api.example.com/x")
        expect(a[:proxy_host]).to be_nil
        expect(a[:proxy_port]).to be_nil
      end
    end
  end

  describe "TLS defaults" do
    it "enables TLS with VERIFY_PEER for https" do
      with_env({}) do
        opts = start_args_for("https://api.example.com/x")[:opts]
        expect(opts[:use_ssl]).to be(true)
        expect(opts[:verify_mode]).to eq(OpenSSL::SSL::VERIFY_PEER)
      end
    end

    it "does not enable TLS for http" do
      with_env({}) do
        opts = start_args_for("http://plain.example.com/x")[:opts]
        expect(opts[:use_ssl]).to be(false)
        expect(opts).not_to have_key(:verify_mode)
      end
    end

    it "passes caller opts (timeouts) through to Net::HTTP.start" do
      captured = nil
      allow(Net::HTTP).to receive(:start) { |*args, &_b| captured = args.last; "r" }
      with_env({}) { described_class.start(URI("https://x.example.com/"), open_timeout: 7, read_timeout: 21) { |h| h } }
      expect(captured).to include(open_timeout: 7, read_timeout: 21, use_ssl: true)
    end
  end

  describe ".get" do
    it "returns the response body as a string" do
      fake_response = instance_double(Net::HTTPOK, body: '{"ok":true}')
      fake_http = instance_double(Net::HTTP)
      allow(fake_http).to receive(:request).and_return(fake_response)
      # Net::HTTP.start returns the block's value — mirror that so get_response
      # receives the response object, not a pre-extracted body.
      allow(Net::HTTP).to receive(:start) { |*_args, &blk| blk.call(fake_http) }
      with_env({}) do
        expect(described_class.get("https://api.example.com/data")).to eq('{"ok":true}')
      end
    end
  end
end
