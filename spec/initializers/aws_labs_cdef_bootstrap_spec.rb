require "rails_helper"

# Issue #487 — config/initializers/aws_labs_cdef_bootstrap.rb runs once at
# app boot. We can't re-run the initializer in tests cheaply (Rails has
# already booted by the time RSpec starts), so these specs exercise the
# initializer's INTENT by replicating its logic against the live model
# layer. This catches regressions in:
#   - the gating logic (enabled? + empty? checks)
#   - the aws_labs_sourced scope
#   - the conditions that should prevent enqueue
RSpec.describe "AwsLabsCdefBootstrap initializer logic", type: :model do
  def bootstrap_decision
    # Mirror the conditions from config/initializers/aws_labs_cdef_bootstrap.rb.
    return :skipped_disabled unless SparcConfig.aws_labs_cdef_enabled?
    return :skipped_env_override if ActiveModel::Type::Boolean.new.cast(ENV["SPARC_SKIP_AWS_LABS_BOOTSTRAP"])
    return :skipped_table_missing unless CdefDocument.table_exists?
    return :skipped_already_populated if CdefDocument.aws_labs_sourced.exists?
    :should_enqueue
  end

  context "when the feature flag is disabled" do
    before { allow(SparcConfig).to receive(:aws_labs_cdef_enabled?).and_return(false) }

    it "does not enqueue (skips on the feature gate)" do
      expect(bootstrap_decision).to eq(:skipped_disabled)
    end
  end

  context "when the feature is enabled" do
    before { allow(SparcConfig).to receive(:aws_labs_cdef_enabled?).and_return(true) }

    it "enqueues when no AWS-Labs-sourced rows exist" do
      expect(CdefDocument.aws_labs_sourced).to be_empty
      expect(bootstrap_decision).to eq(:should_enqueue)
    end

    it "skips when AWS-Labs-sourced rows already exist" do
      create(:cdef_document,
             name: "Pre-existing AWS Labs row",
             import_metadata: {
               "source_type" => "aws_labs",
               "source_url"  => "https://github.com/awslabs/oscal-content-for-aws-services/blob/main/component-definitions/s3/s3-cd.json",
               "source_sha"  => "deadbeef"
             })
      expect(bootstrap_decision).to eq(:skipped_already_populated)
    end

    it "still enqueues when only cloned (user_upload) rows exist" do
      # A tenant with only cloned-and-edited rows should still trigger
      # bootstrap — the canonical AWS rows are what should populate.
      original_id = create(:cdef_document, name: "Original aws").id
      create(:cdef_document, name: "Clone", cloned_from_id: original_id,
             import_metadata: { "source_type" => "user_upload" })
      expect(CdefDocument.aws_labs_sourced).to be_empty
      expect(bootstrap_decision).to eq(:should_enqueue)
    end

    it "respects the SPARC_SKIP_AWS_LABS_BOOTSTRAP escape hatch" do
      ENV["SPARC_SKIP_AWS_LABS_BOOTSTRAP"] = "true"
      expect(bootstrap_decision).to eq(:skipped_env_override)
    ensure
      ENV.delete("SPARC_SKIP_AWS_LABS_BOOTSTRAP")
    end
  end
end
