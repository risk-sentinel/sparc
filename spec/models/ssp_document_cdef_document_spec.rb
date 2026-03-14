require "rails_helper"

RSpec.describe SspDocumentCdefDocument, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:ssp_document) }
    it { is_expected.to belong_to(:cdef_document) }
  end
end
