# frozen_string_literal: true

require "rails_helper"

# #1271 — a copy that fails says so. Every action that duplicates a document
# (DocumentCopyReporting) shows the reason on the source document, audits it
# against the source, and leaves no partial copy behind.
RSpec.describe "A failed document copy is reported (#1271)", type: :request do
  let(:admin) { create(:user, :admin) }

  before { sign_in_as(admin) }

  # The failure the issue was found with: the copy's slug refused on save.
  def refuse_the_copy!(klass)
    allow_any_instance_of(klass).to receive(:save!).and_wrap_original do |original, *args|
      record = original.receiver
      raise ActiveRecord::RecordInvalid.new(record.tap { _1.errors.add(:slug, "has already been taken") }) if record.new_record?

      original.call(*args)
    end
  end

  shared_examples "a reported copy failure" do |audit_action|
    it "shows the reason on the source document, audits it, and leaves no copy" do
      expect { perform }.not_to change(source.class, :count)

      expect(response).to redirect_to(polymorphic_path(source))
      follow_redirect!
      expect(response.body).to include("Could not duplicate &#39;#{source.name}&#39;: Slug has already been taken")

      event = AuditEvent.where(action: audit_action).last
      expect(event).to be_present
      expect(event.metadata).to include("source_id" => source.id, "error_class" => "ActiveRecord::RecordInvalid")
    end
  end

  describe "Copy on a profile" do
    let!(:source) { create(:profile_document, name: "Invented Baseline") }
    let(:perform) { post copy_profile_document_path(source) }

    before { refuse_the_copy!(ProfileDocument) }

    it_behaves_like "a reported copy failure", "profile_document_copy_failed"
  end

  describe "a new profile made from a published one" do
    let!(:source) { create(:profile_document, name: "Invented Published Baseline", lifecycle_status: "published") }
    let(:perform) { post create_from_profile_profile_documents_path, params: { source_profile_id: source.slug } }

    before { refuse_the_copy!(ProfileDocument) }

    it_behaves_like "a reported copy failure", "profile_document_copy_failed"
  end

  describe "a new profile whose link to its source fails" do
    let!(:source) { create(:profile_document, name: "Invented Published Baseline", lifecycle_status: "published") }

    it "leaves no copy behind" do
      allow_any_instance_of(ProfileDocument).to receive(:update!).and_wrap_original do |original, *args|
        raise ActiveRecord::RecordNotSaved, "Invented link failure" if args.first.is_a?(Hash) && args.first.key?(:source_profile_id)

        original.call(*args)
      end

      expect { post create_from_profile_profile_documents_path, params: { source_profile_id: source.slug } }
        .not_to change(ProfileDocument, :count)
      follow_redirect!
      expect(response.body).to include("Could not duplicate &#39;Invented Published Baseline&#39;: Invented link failure")
    end
  end

  describe "Copy on a CDEF" do
    let!(:source) { create(:cdef_document, name: "Invented Component") }
    let(:perform) { post copy_cdef_document_path(source) }

    before { refuse_the_copy!(CdefDocument) }

    it_behaves_like "a reported copy failure", "cdef_document_copy_failed"
  end
end
