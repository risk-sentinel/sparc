class Boundary < ApplicationRecord
  belongs_to :authorization_boundary
  has_many :boundary_cdef_documents, dependent: :destroy
  has_many :cdef_documents, through: :boundary_cdef_documents

  enum :environment, {
    production: "production",
    development: "development",
    staging: "staging",
    test: "test"
  }

  validates :name, presence: true
  validates :environment, presence: true

  ENVIRONMENTS = %w[production development staging test].freeze
end
