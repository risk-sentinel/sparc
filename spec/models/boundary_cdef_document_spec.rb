require "rails_helper"

RSpec.describe BoundaryCdefDocument, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:boundary) }
    it { is_expected.to belong_to(:cdef_document) }
  end
end
