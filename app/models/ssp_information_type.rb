class SspInformationType < ApplicationRecord
  belongs_to :ssp_document
  # #940 S3 — an information type is an input to the BOUNDARY's FIPS-199
  # categorization, so it belongs to the boundary too. Optional: a type authored
  # against an SSP with no boundary yet is still valid data.
  belongs_to :authorization_boundary, optional: true

  # FIPS-199 impact levels, ordered. OSCAL's vocabulary, so the values round-trip
  # through export without translation.
  IMPACT_LEVELS = %w[fips-199-low fips-199-moderate fips-199-high].freeze

  # The impact actually in force for an objective: the owner's SELECTED value if
  # they made one, otherwise the provisional BASE from SP 800-60 Vol 2. That is
  # the order FIPS-199 intends — an adjustment overrides the provisional value,
  # it does not sit alongside it.
  def effective_impact(objective)
    public_send("#{objective}_impact_selected").presence ||
      public_send("#{objective}_impact_base").presence
  end

  validates :uuid, presence: true
  validates :title, presence: true
  validates :description, presence: true
end
