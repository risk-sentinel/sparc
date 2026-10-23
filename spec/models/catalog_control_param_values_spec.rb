# frozen_string_literal: true

require "rails_helper"

# #1241 — CatalogControl#merge_params_values, the one write path the catalog
# editor and the API share for a parameter's assigned `values`. Values are
# invented.
RSpec.describe CatalogControl do
  let(:control) do
    build(:catalog_control, control_id: "ex-1", params_data: [
      { "id" => "ex-01_odp.01", "label" => "personnel or roles" },
      { "id" => "ex-01_odp.02", "select" => { "choice" => %w[daily weekly] } },
      { "id" => "ex-01_odp.03", "select" => { "how-many" => "one-or-more", "choice" => %w[daily weekly] } }
    ])
  end

  def merged(values) = control.merge_params_values(values).index_by { |p| p["id"] }

  describe "#merge_params_values" do
    it "sets values and leaves the label and everything else alone" do
      param = merged("ex-01_odp.01" => "Example Agency personnel")["ex-01_odp.01"]

      expect(param).to eq("id" => "ex-01_odp.01", "label" => "personnel or roles", "values" => [ "Example Agency personnel" ])
    end

    it "splits several values on ' | ' and never on a comma" do
      param = merged("ex-01_odp.01" => "Example Agency, Inc. personnel | Example auditors")["ex-01_odp.01"]

      expect(param["values"]).to eq([ "Example Agency, Inc. personnel", "Example auditors" ])
    end

    it "removes the catalog's value when given a blank one" do
      control.params_data = control.merge_params_values("ex-01_odp.01" => "x")

      expect(merged("ex-01_odp.01" => "")["ex-01_odp.01"]).not_to have_key("values")
    end

    it "refuses a select value that is not one of the choices" do
      expect { control.merge_params_values("ex-01_odp.02" => "hourly") }
        .to raise_error(described_class::InvalidParamValue, /"hourly" is not one of its choices/)
    end

    it "reads an absent how-many as one, as OSCAL does" do
      expect { control.merge_params_values("ex-01_odp.02" => %w[daily weekly]) }
        .to raise_error(described_class::InvalidParamValue, /choose one/)
      expect(merged("ex-01_odp.03" => %w[daily weekly])["ex-01_odp.03"]["values"]).to eq(%w[daily weekly])
    end

    it "refuses a parameter the control does not have" do
      expect { control.merge_params_values("ex-01_odp.99" => "x") }
        .to raise_error(described_class::InvalidParamValue, /ex-01_odp.99/)
    end
  end

  describe ".oscal_param" do
    it "emits an answered select as its answer, since OSCAL allows values or select, not both" do
      param = { "id" => "p", "select" => { "choice" => %w[a b] }, "values" => [ "a" ] }

      expect(described_class.oscal_param(param)).to eq("id" => "p", "values" => [ "a" ])
    end

    it "leaves an unanswered select, and a plain parameter, as they are" do
      select = { "id" => "p", "select" => { "choice" => %w[a b] } }
      plain = { "id" => "q", "values" => [ "x" ] }

      expect(described_class.oscal_param(select)).to eq(select)
      expect(described_class.oscal_param(plain)).to eq(plain)
    end
  end
end
