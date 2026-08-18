# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260818170000_report_incomplete_evidence.rb")

# #947 — the advisory report for evidence and attestations the new completeness
# rules leave behind.
#
# The migration is deferred, so these drive the private reporters directly
# rather than through `up` (which would only enqueue them).
#
# What matters here is that it FINDS things and CHANGES nothing. A report that
# silently misses rows is worse than no report: an operator reads zero and
# concludes there is nothing to do.
RSpec.describe ReportIncompleteEvidence do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  # The rules forbid these states, so producing one means bypassing validation —
  # which is exactly what makes it a pre-rule row.
  def persisted_without_validation(evidence)
    evidence.slug ||= "incomplete-#{SecureRandom.hex(4)}"
    evidence.save!(validate: false)
    evidence
  end

  def unlinked_evidence(**attrs)
    persisted_without_validation(build(:evidence, :without_control_links, **attrs))
  end

  describe "evidence supporting no control" do
    it "counts a row with no control links" do
      unlinked_evidence

      expect(migration.send(:report_unlinked_evidence)).to eq(1)
    end

    it "does not count evidence that supports a control" do
      create(:evidence)

      expect(migration.send(:report_unlinked_evidence)).to eq(0)
    end

    # The exemption has to be visible AND separated, or the headline number
    # reads as a backlog that includes rows nobody has to act on.
    it "separates an auto-fetched authoritative source from the authored count" do
      unlinked_evidence(collected_by: AuthoritativeSourceFetchService::SYSTEM_COLLECTOR)

      expect(migration.send(:report_unlinked_evidence)).to eq(0)
    end

    it "still counts an authored row alongside a fetched one" do
      unlinked_evidence(collected_by: AuthoritativeSourceFetchService::SYSTEM_COLLECTOR)
      unlinked_evidence(collected_by: "A Person")

      expect(migration.send(:report_unlinked_evidence)).to eq(1)
    end
  end

  describe "an artefact type carrying no file" do
    it "counts artefact evidence with no attachment" do
      persisted_without_validation(build(:evidence, :without_file))

      expect(migration.send(:report_fileless_artefact_evidence)).to eq(1)
    end

    it "does not count an attestation, which is satisfied by its statement" do
      create(:evidence, :attestation)

      expect(migration.send(:report_fileless_artefact_evidence)).to eq(0)
    end

    it "does not count artefact evidence that carries its file" do
      create(:evidence)

      expect(migration.send(:report_fileless_artefact_evidence)).to eq(0)
    end
  end

  describe "attestations whose claim was never checked" do
    it "counts a legacy row with no resolved account" do
      attestation = build(:attestation, :legacy_control_owner)
      attestation.save!(validate: false)

      expect(migration.send(:report_unverifiable_attestations)).to eq(1)
    end

    it "does not count an attestation whose attester holds the claimed role" do
      create(:attestation)

      expect(migration.send(:report_unverifiable_attestations)).to eq(0)
    end

    # The rule is a live check, not a one-off stamp: losing the role makes an
    # existing attestation unverifiable, and the report has to say so.
    it "counts an attestation whose attester has since lost the role" do
      attestation = create(:attestation)
      UserRole.where(user_id: attestation.attester_user_id).destroy_all

      expect(migration.send(:report_unverifiable_attestations)).to eq(1)
    end
  end

  describe "what it writes" do
    it "changes no evidence and no attestation" do
      unlinked = unlinked_evidence
      legacy = build(:attestation, :legacy_control_owner)
      legacy.save!(validate: false)

      expect {
        migration.send(:report_unlinked_evidence)
        migration.send(:report_fileless_artefact_evidence)
        migration.send(:report_unverifiable_attestations)
      }.not_to change {
        [ unlinked.reload.attributes, legacy.reload.attributes ]
      }
    end

    # The signature is the non-repudiation record. Reporting must never touch it.
    it "leaves a legacy attestation's signature_hash intact" do
      legacy = build(:attestation, :legacy_control_owner)
      legacy.save!(validate: false)
      legacy.update_column(:signature_hash, "a" * 64)

      migration.send(:report_unverifiable_attestations)

      expect(legacy.reload.signature_hash).to eq("a" * 64)
    end
  end
end
