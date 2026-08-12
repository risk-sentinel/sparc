# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260812120100_backfill_evidence_collected_by_user.rb")

# #934 — resolving the historical `collected_by` name to the account it names.
#
# The migration is deferred, so this drives `backfill_collected_by_user`
# directly rather than through `up` (which would only enqueue it).
#
# Every `collected_by` here is set EXPLICITLY. The evidence factory defaults it
# to `Faker::Name.name`, and a Faker name that happens to equal a created user's
# name would make a matching assertion pass for the wrong reason — or an
# ambiguity assertion fail at random.
RSpec.describe BackfillEvidenceCollectedByUser do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  def evidence_collected_by(name, **attrs)
    create(:evidence, collected_by: name, collected_by_user: nil, **attrs)
  end

  describe "what it resolves" do
    it "links a row whose name matches exactly one account's display name" do
      user = create(:user, display_name: "Ada Lovelace")
      evidence = evidence_collected_by("Ada Lovelace")

      migration.backfill_collected_by_user

      expect(evidence.reload.collected_by_user_id).to eq(user.id)
    end

    it "links on email, which is what the fallback wrote for a user with no display name" do
      user = create(:user, display_name: nil, first_name: nil, last_name: nil,
                    email: "grace@example.gov")
      evidence = evidence_collected_by("grace@example.gov")

      migration.backfill_collected_by_user

      expect(evidence.reload.collected_by_user_id).to eq(user.id)
    end

    it "links on first+last, the middle rung of display_label's fallback" do
      user = create(:user, display_name: nil, first_name: "Katherine", last_name: "Johnson")
      evidence = evidence_collected_by("Katherine Johnson")

      migration.backfill_collected_by_user

      expect(evidence.reload.collected_by_user_id).to eq(user.id)
    end

    it "ignores case and surrounding whitespace" do
      user = create(:user, display_name: "Ada Lovelace")
      evidence = evidence_collected_by("  ADA lovelace ")

      migration.backfill_collected_by_user

      expect(evidence.reload.collected_by_user_id).to eq(user.id)
    end

    it "links every row sharing one name in a single pass" do
      user = create(:user, display_name: "Ada Lovelace")
      rows = Array.new(3) { evidence_collected_by("Ada Lovelace") }

      expect(migration.backfill_collected_by_user).to eq(3)
      expect(rows.map { |r| r.reload.collected_by_user_id }).to all(eq(user.id))
    end
  end

  # A wrong attribution in an evidence package is worse than a missing one: the
  # missing one is visibly missing.
  describe "what it refuses to guess" do
    it "leaves a name shared by two accounts unattributed" do
      create(:user, display_name: "Twin Name")
      create(:user, display_name: "Twin Name")
      evidence = evidence_collected_by("Twin Name")

      migration.backfill_collected_by_user

      expect(evidence.reload.collected_by_user_id).to be_nil
    end

    it "leaves a name that is one account's display name and another's email unattributed" do
      create(:user, email: "overlap@example.gov", display_name: "Someone Else")
      create(:user, display_name: "overlap@example.gov")
      evidence = evidence_collected_by("overlap@example.gov")

      migration.backfill_collected_by_user

      expect(evidence.reload.collected_by_user_id).to be_nil
    end

    it "leaves a name matching no account unattributed" do
      create(:user, display_name: "Ada Lovelace")
      evidence = evidence_collected_by("Nobody In Particular")

      migration.backfill_collected_by_user

      expect(evidence.reload.collected_by_user_id).to be_nil
    end

    it "leaves a row with no collector name at all alone" do
      evidence = evidence_collected_by(nil)

      expect { migration.backfill_collected_by_user }
        .not_to change { evidence.reload.collected_by_user_id }.from(nil)
    end
  end

  # `collected_by` records what was true at collection time. Deriving it from
  # the FK — even to "correct" a since-renamed account — destroys the property
  # that makes it audit evidence.
  describe "the historical snapshot" do
    it "never writes collected_by, even where it resolves the account" do
      user = create(:user, display_name: "Ada Lovelace")
      evidence = evidence_collected_by("  ADA lovelace ")

      migration.backfill_collected_by_user

      expect(evidence.reload.collected_by).to eq("  ADA lovelace ")
      expect(evidence.collected_by_user_id).to eq(user.id)
    end

    it "leaves a since-renamed account's old name in place" do
      user = create(:user, display_name: "Ada Lovelace")
      evidence = evidence_collected_by("Ada Lovelace")
      migration.backfill_collected_by_user

      user.update!(display_name: "Ada Byron")
      migration.backfill_collected_by_user

      expect(evidence.reload.collected_by).to eq("Ada Lovelace")
      expect(evidence.collected_by_user_id).to eq(user.id)
    end
  end

  describe "idempotency and resume-from-partial" do
    it "is a no-op on a second run" do
      create(:user, display_name: "Ada Lovelace")
      evidence_collected_by("Ada Lovelace")

      expect(migration.backfill_collected_by_user).to eq(1)
      expect(migration.backfill_collected_by_user).to eq(0)
    end

    it "resumes, linking only what a partial run left unattributed" do
      user = create(:user, display_name: "Ada Lovelace")
      done    = evidence_collected_by("Ada Lovelace", collected_by_user: user)
      pending = evidence_collected_by("Ada Lovelace")

      expect(migration.backfill_collected_by_user).to eq(1)
      expect(pending.reload.collected_by_user_id).to eq(user.id)
      expect(done.reload.collected_by_user_id).to eq(user.id)
    end

    # An operator who corrected an attribution by hand must not have it stamped
    # back over by the next run — which is what "already attributed is never
    # revisited" has to mean in practice.
    it "does not overwrite an attribution that disagrees with the name" do
      create(:user, display_name: "Ada Lovelace")
      corrected_to = create(:user, display_name: "Someone Else")
      evidence = evidence_collected_by("Ada Lovelace", collected_by_user: corrected_to)

      migration.backfill_collected_by_user

      expect(evidence.reload.collected_by_user_id).to eq(corrected_to.id)
    end
  end

  describe "down" do
    it "is a no-op rather than stripping correct attributions" do
      user = create(:user, display_name: "Ada Lovelace")
      evidence = evidence_collected_by("Ada Lovelace")
      migration.backfill_collected_by_user

      migration.down

      expect(evidence.reload.collected_by_user_id).to eq(user.id)
    end
  end
end
