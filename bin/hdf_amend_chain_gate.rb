#!/usr/bin/env ruby
# frozen_string_literal: true

# #1184 — fail unless the amendment chain is ESTABLISHED, not merely unbroken.
#
#   bin/hdf_amend_chain_gate.rb amendments.hdf.json
#
# Runs `hdf amend verify` and judges its OUTPUT, not its exit code. Measured
# on hdf-cli 3.7.0 against the same register in three states:
#
#   | document  | verify rc | chain line               |
#   |-----------|-----------|--------------------------|
#   | chained   | 0         | Chain: ✓ verified        |
#   | UNCHAINED | 0         | Chain: not established   |   <- passes on rc
#   | tampered  | 1         | Chain: ✗ broken          |
#
# So tamper detection works, and an ABSENT chain passes. If a refactor of
# Hdf::AmendmentChain, a new emitter that forgets `chain!`, or an upstream
# shape change stopped writing `previousChecksum`, every build would stay green
# and the tamper evidence would be silently gone — the same shape as CI-1's
# gate that reported success because it assessed nothing.
#
# Absent protection and defeated protection are the same outcome, so both
# fail here. So does any output this does not recognise: a gate that passes
# on text it cannot read is the defect, not the fallback.
#
# NIST SP 800-53 Rev 5: AU-9 (protection of audit information — tamper
# evidence on the disposition record), SI-7, CA-7.
require "open3"

VERIFIED = /^Chain:\s+✓ verified\s*$/

def gate(path, hdf: ENV.fetch("HDF_BIN", "hdf"))
  output, status = Open3.capture2e(hdf, "amend", "verify", path)
  puts output

  return [ false, "hdf amend verify exited #{status.exitstatus}" ] unless status.success?

  chain = output[/^Chain:.*$/]
  return [ false, "hdf amend verify printed no Chain line — cannot confirm the chain; refusing to pass" ] unless chain
  return [ false, "the amendment chain is not verified (#{chain.strip}) — an absent chain is as unprotected as a broken one" ] unless chain.match?(VERIFIED)

  [ true, "amendment chain verified" ]
rescue SystemCallError => e
  [ false, "could not run hdf (#{e.message})" ]
end

if __FILE__ == $PROGRAM_NAME
  path = ARGV.fetch(0) { abort "usage: bin/hdf_amend_chain_gate.rb AMENDMENTS.json" }
  abort "hdf_amend_chain_gate: #{path} does not exist — failing closed" unless File.file?(path)

  ok, message = gate(path)
  if ok
    puts "hdf_amend_chain_gate: #{message}"
  else
    warn "::error::hdf_amend_chain_gate: #{message}"
    exit 1
  end
end
