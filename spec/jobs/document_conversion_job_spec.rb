require "rails_helper"

RSpec.describe DocumentConversionJob, type: :job do
  include ActiveJob::TestHelper

  let(:fixture_path) { Rails.root.join("spec/fixtures/files/profiles/small-resolved-profile-catalog.json") }
  let(:document)     { create(:profile_document, file_type: "json", status: "pending") }

  def attach_fixture!(doc, path = fixture_path)
    doc.file.attach(io: File.open(path), filename: File.basename(path), content_type: "application/json")
  end

  describe "#queue_name" do
    it "is enqueued in the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end

  describe "#perform happy path" do
    before { ENV["SPARC_PERSIST_S3_BLOB"] = "true" }
    after  { ENV.delete("SPARC_PERSIST_S3_BLOB") }

    it "marks the document completed when the parse succeeds" do
      attach_fixture!(document)
      described_class.new.perform(:profile, document.id)
      expect(document.reload.status).to eq("completed")
    end

    it "ignores the legacy third positional arg (one-release deprecation window)" do
      attach_fixture!(document)
      expect {
        described_class.new.perform(:profile, document.id, "/some/stale/tmp/path.json")
      }.not_to raise_error
      expect(document.reload.status).to eq("completed")
    end
  end

  describe "missing attachment" do
    it "marks the document failed with an error message" do
      # No attach_fixture! — the document has no file
      described_class.new.perform(:profile, document.id)

      document.reload
      expect(document.status).to eq("failed")
      expect(document.error_message).to match(/has no attached file/)
    end
  end

  describe "parser error" do
    before { ENV["SPARC_PERSIST_S3_BLOB"] = "true" }
    after  { ENV.delete("SPARC_PERSIST_S3_BLOB") }

    it "marks the document failed when the parser raises" do
      attach_fixture!(document)
      allow_any_instance_of(ProfileJsonParserService).to receive(:parse).and_raise("boom")

      described_class.new.perform(:profile, document.id)

      document.reload
      expect(document.status).to eq("failed")
      expect(document.error_message).to eq("boom")
    end

    it "RETAINS the attached blob on failure (#392 — user can retry / inspect)" do
      attach_fixture!(document)
      allow_any_instance_of(ProfileJsonParserService).to receive(:parse).and_raise("boom")

      described_class.new.perform(:profile, document.id)
      perform_enqueued_jobs # drain any purge jobs (there should be none)

      expect(document.reload.file).to be_attached
    end
  end

  describe "S3 blob retention (#392 / #680)" do
    it "retains the blob after a successful parse by default (#680)" do
      attach_fixture!(document)
      ENV.delete("SPARC_PERSIST_S3_BLOB")

      perform_enqueued_jobs do
        described_class.new.perform(:profile, document.id)
      end

      expect(document.reload.file).to be_attached
    end

    it "keeps the blob when SPARC_PERSIST_S3_BLOB=true" do
      attach_fixture!(document)
      ENV["SPARC_PERSIST_S3_BLOB"] = "true"

      perform_enqueued_jobs do
        described_class.new.perform(:profile, document.id)
      end

      expect(document.reload.file).to be_attached
    ensure
      ENV.delete("SPARC_PERSIST_S3_BLOB")
    end

    it "purges the blob only when SPARC_PERSIST_S3_BLOB=false (opt-in)" do
      attach_fixture!(document)
      ENV["SPARC_PERSIST_S3_BLOB"] = "false"

      perform_enqueued_jobs do
        described_class.new.perform(:profile, document.id)
      end

      expect(document.reload.file).not_to be_attached
    ensure
      ENV.delete("SPARC_PERSIST_S3_BLOB")
    end
  end

  describe "Sidekiq retry on transient S3 errors" do
    it "registers retry_on for Aws::Errors::ServiceError" do
      # ActiveJob exposes registered exceptions as procs in @rescue_handlers; assert
      # the class registered the exception we care about.
      handlers = described_class.rescue_handlers.map { |klass, _| klass.to_s }
      expect(handlers).to include("Aws::Errors::ServiceError")
    end

    it "registers retry_on for Net::OpenTimeout / Net::ReadTimeout" do
      handlers = described_class.rescue_handlers.map { |klass, _| klass.to_s }
      expect(handlers).to include("Net::OpenTimeout", "Net::ReadTimeout")
    end
  end
end
