# frozen_string_literal: true

require "rails_helper"

# #911 — `ControlId.forms` exists because canonicalisation happens on WRITE.
#
# A row adopts the canonical form only when it is next saved, so during the
# transition a column holds a mix of spellings. A query that canonicalises only
# its input would then match nothing — the same silent failure canonicalisation
# exists to end. Comparisons match the set of legitimate forms instead.
RSpec.describe ControlId, ".forms" do
  it "returns every legitimate spelling of one identifier" do
    forms = described_class.forms("AC-2")

    expect(forms).to include("ac-2")     # canonical, what catalogs store
    expect(forms).to include("AC-02")    # padded, what SPARC displays
    expect(forms).to include("AC-2")     # exactly what the caller passed
  end

  it "covers the enhancement spellings" do
    forms = described_class.forms("ac-2.1")

    expect(forms).to include("ac-2.1")
    expect(forms).to include("AC-02.01")
    expect(forms).to include("AC-2 (1)")
  end

  it "finds a row stored in any form" do
    # The transitional reality: SarControl is entirely padded, evidence links
    # are canonical. One query has to match both.
    %w[AC-02 ac-2 AC-2].each do |stored|
      %w[AC-02 ac-2 AC-2 AC-2\ (1)].each do |queried|
        next unless described_class.same?(stored, queried)

        expect(described_class.forms(queried)).to include(stored),
          "querying #{queried.inspect} would not match a row stored as #{stored.inspect}"
      end
    end
  end

  it "is empty for blank input rather than matching everything" do
    expect(described_class.forms(nil)).to eq([])
    expect(described_class.forms("")).to eq([])
    expect(described_class.forms("   ")).to eq([])
  end

  it "does not invent forms for a fixed-width external identifier" do
    # CCI ids are six-digit fixed-width; stripping zeros would produce an
    # identifier that names nothing.
    expect(described_class.forms("CCI-000213")).to include("cci-000213")
    expect(described_class.forms("CCI-000213")).not_to include("cci-213")
  end

  it "returns each spelling once" do
    forms = described_class.forms("ac-2")

    expect(forms.uniq).to eq(forms)
  end

  # Catalogs do not agree on case for the padded form. The FedRAMP KSI catalog
  # stores `ksi-auth-01` — padded AND lowercase — so emitting only the uppercase
  # padded form would miss every KSI row.
  it "matches a catalog that stores the padded form in lowercase" do
    expect(described_class.forms("ksi-auth-1")).to include("ksi-auth-01")
    expect(described_class.forms("KSI-AUTH-01")).to include("ksi-auth-01")
  end
end
