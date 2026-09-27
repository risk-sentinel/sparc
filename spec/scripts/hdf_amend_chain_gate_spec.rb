# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"

# #1184 — the gate judges the chain LINE, never the exit code.
#
# `hdf amend verify` exits 0 on an UNCHAINED document, so an exit-code gate
# passes the one case this exists to catch. `hdf` is replaced by a stub that
# prints each state hdf-cli 3.7.0 was measured printing (the real binary was
# also run against a chained, an unchained and a tampered register when this
# was written; see the script header).
RSpec.describe "bin/hdf_amend_chain_gate.rb" do
  let(:script) { Rails.root.join("bin/hdf_amend_chain_gate.rb").to_s }

  around { |example| Dir.mktmpdir("chain-gate-") { |dir| @dir = dir; example.run } }

  def gate(chain_line:, exit_code: 0)
    stub = File.join(@dir, "hdf")
    File.write(stub, <<~SH)
      #!/usr/bin/env bash
      echo "Total amendments: 32"
      #{chain_line ? %(echo "#{chain_line}") : ''}
      exit #{exit_code}
    SH
    File.chmod(0o755, stub)
    amendments = File.join(@dir, "amendments.json").tap { |p| File.write(p, "{}") }
    Open3.capture2e({ "HDF_BIN" => stub }, "ruby", script, amendments)
  end

  it "passes a verified chain" do
    out, status = gate(chain_line: "Chain:            ✓ verified")

    expect(status).to be_success, out
  end

  it "FAILS an unestablished chain even though hdf exits 0 — the hole #1184 names" do
    out, status = gate(chain_line: "Chain:            not established", exit_code: 0)

    expect(status).not_to be_success
    expect(out).to match(/not verified \(Chain:\s+not established\)/)
  end

  it "fails a broken chain" do
    _out, status = gate(chain_line: "Chain:            ✗ broken", exit_code: 1)

    expect(status).not_to be_success
  end

  it "fails when hdf prints no chain line at all, rather than passing on text it cannot read" do
    out, status = gate(chain_line: nil)

    expect(status).not_to be_success
    expect(out).to match(/no Chain line/)
  end

  it "fails closed on a missing amendments file" do
    out, status = Open3.capture2e("ruby", script, File.join(@dir, "absent.json"))

    expect(status).not_to be_success
    expect(out).to match(/failing closed/)
  end
end
