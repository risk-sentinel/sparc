require "rails_helper"

RSpec.describe Boundary, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:environment) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to have_many(:boundary_cdef_documents).dependent(:destroy) }
    it { is_expected.to have_many(:cdef_documents).through(:boundary_cdef_documents) }
  end

  describe "enums" do
    it {
      is_expected.to define_enum_for(:environment)
        .backed_by_column_of_type(:string)
        .with_values(production: "production", development: "development", staging: "staging", test: "test")
    }
  end
end
