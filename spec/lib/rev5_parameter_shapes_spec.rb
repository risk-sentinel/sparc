# frozen_string_literal: true

require "rails_helper"

# NIST's Rev 5 catalog declares parameters in more than one shape, and a
# screen has to read each one as NIST means it:
#
#   - an ordinary ODP (`ac-01_odp.05`): a value an organization sets;
#   - an AGGREGATE (`ac-1_prm_1`, 142 of them): its `aggregates` props name
#     the ODPs it combines, and it has no value of its own;
#   - an aggregate that is ALSO a selection (`sc-36_prm_1`, `si-7.1_prm_2`);
#   - an ODP whose guideline names another parameter (`sa-11_odp.02`, one
#     of five).
#
# The parameter table showed the aggregate as an empty field to fill in, and
# showed the five guidelines with their `{{ insert: param, … }}` markup.
RSpec.describe "Rev 5 parameter shapes" do
  let(:rmf) { "http://csrc.nist.gov/ns/rmf" }

  def aggregates(*ids) = ids.map { |id| { "name" => "aggregates", "ns" => rmf, "value" => id } }

  let(:ac1_params) do
    [
      { "id" => "ac-1_prm_1", "label" => "organization-defined personnel or roles",
        "props" => aggregates("ac-01_odp.01", "ac-01_odp.02") },
      { "id" => "ac-01_odp.01", "label" => "personnel or roles",
        "guidelines" => [ { "prose" => "personnel or roles to whom the access control policy is to be disseminated is/are defined;" } ] },
      { "id" => "ac-01_odp.02", "label" => "personnel or roles" },
      { "id" => "ac-01_odp.05", "label" => "frequency" }
    ]
  end

  let(:sc36_params) do
    [
      { "id" => "sc-36_prm_1", "props" => aggregates("sc-36_odp.02", "sc-36_odp.04"),
        "select" => { "choice" => [ "physical locations", "logical domains" ] } },
      { "id" => "sc-36_odp.02", "select" => { "choice" => [ "physical locations", "logical domains" ] } },
      { "id" => "sc-36_odp.04", "select" => { "choice" => [ "physical locations", "logical domains" ] } }
    ]
  end

  let(:sa11_params) do
    [
      { "id" => "sa-11_odp.01", "label" => "testing/evaluation",
        "select" => { "how-many" => "one-or-more", "choice" => [ "unit", "integration", "system", "regression" ] } },
      { "id" => "sa-11_odp.02", "label" => "frequency",
        "guidelines" => [ { "prose" => "frequency at which to conduct {{ insert: param, sa-11_odp.01 }} testing/evaluation is defined;" } ] }
    ]
  end

  def control(id, params)
    family = create(:control_family, control_catalog: create(:control_catalog), code: id.split("-").first.upcase)
    create(:catalog_control, control_family: family, control_id: id, title: id, params_data: params)
  end

  def detail(id, params, values = {}) = BaselineControlDetail.new(control(id, params), values: values)
  def param(detail, id) = detail.parameters.find { |p| p.id == id }

  describe OscalParameterResolver do
    it "names the parameters an aggregate combines, and none for an ordinary one" do
      expect(described_class.aggregated_ids(ac1_params[0])).to eq(%w[ac-01_odp.01 ac-01_odp.02])
      expect(described_class.aggregated_ids(ac1_params[3])).to eq([])
      expect(described_class.aggregated_ids(nil)).to eq([])
    end

    it "reads an aggregate that is also a selection from its parts, not from every option" do
      resolver = described_class.new(sc36_params, "sc-36_odp.02" => "logical domains", "sc-36_odp.04" => "logical domains")

      expect(resolver.resolve_param("sc-36_prm_1")).to eq("logical domains")
    end

    it "still reads a choice made on such an aggregate itself" do
      resolver = described_class.new(sc36_params, "sc-36_prm_1" => "physical locations", "sc-36_odp.02" => "logical domains")

      expect(resolver.resolve_param("sc-36_prm_1")).to eq("physical locations")
    end
  end

  describe BaselineControlDetail do
    it "marks an aggregate, and reads it from its parts" do
      d = detail("ac-1", ac1_params, "ac-01_odp.01" => "ISSO", "ac-01_odp.02" => "System owners")
      agg = param(d, "ac-1_prm_1")

      expect(agg).to be_aggregate
      expect(agg.aggregates).to eq(%w[ac-01_odp.01 ac-01_odp.02])
      expect(agg.aggregate_answered).to be(true)
      expect(agg.display).to eq("ISSO, System owners")
      expect(param(d, "ac-01_odp.05")).not_to be_aggregate
    end

    it "shows a value set on the aggregate itself, which the API accepts and the resolver reads first" do
      agg = param(detail("ac-1", ac1_params, "ac-1_prm_1" => "the Security Steering Committee"), "ac-1_prm_1")

      expect(agg.aggregate_answered).to be(true)
      expect(agg.display).to eq("the Security Steering Committee")
    end

    it "knows an aggregate none of whose parts is set" do
      agg = param(detail("ac-1", ac1_params), "ac-1_prm_1")

      expect(agg.aggregate_answered).to be(false)
    end

    it "resolves a guideline that names another parameter" do
      d = detail("sa-11", sa11_params, "sa-11_odp.01" => "unit, regression")

      expect(param(d, "sa-11_odp.02").description).to eq("frequency at which to conduct unit regression testing/evaluation is defined;")
      expect(param(d, "sa-11_odp.02").description).not_to include("insert:")
    end
  end

  describe "the parameter table", type: :view do
    def render_table(d, editable:)
      render partial: "shared/baseline_control_detail",
             locals: { detail: d, editable: editable, form_url: (editable ? "/x" : nil) }
      Nokogiri::HTML(rendered)
    end

    [ true, false ].each do |editable|
      context(editable ? "when editable" : "when read-only") do
        it "shows an aggregate's reading and the parameters that set it, with no field of its own" do
          html = render_table(detail("ac-1", ac1_params, "ac-01_odp.01" => "ISSO", "ac-01_odp.02" => "System owners"), editable: editable)
          row = html.at_css("[data-aggregate-param='ac-1_prm_1']")

          expect(row.text.squish).to include("ISSO, System owners")
          expect(row.text.squish).to include("Combines ac-01_odp.01 and ac-01_odp.02")
          expect(html.css("[name^='param_values[ac-1_prm_1]']")).to be_empty
          expect(html.css("[name='param_values[ac-01_odp.05]']").size).to eq(editable ? 1 : 0)
        end

        it "says Not set for an aggregate none of whose parts is set" do
          html = render_table(detail("ac-1", ac1_params), editable: editable)

          expect(html.at_css("[data-aggregate-param='ac-1_prm_1']").text.squish).to start_with("Not set")
        end
      end
    end
  end
end
