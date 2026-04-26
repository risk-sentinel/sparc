require "rails_helper"

RSpec.describe AuthoritativeSourceFetchService do
  let(:actor)    { create(:user, :admin) }
  let(:resource) do
    BackMatterResource.create!(uuid: SecureRandom.uuid, title: "Doc", source: "managed",
                               href: "https://example.gov/policy.pdf",
                               media_type: "application/pdf")
  end

  around do |ex|
    previous = ENV["SPARC_AUTHORITATIVE_FETCH_ENABLED"]
    ENV["SPARC_AUTHORITATIVE_FETCH_ENABLED"] = "true"
    ex.run
    ENV["SPARC_AUTHORITATIVE_FETCH_ENABLED"] = previous
  end

  def stub_response(status_class, body: "PDF-CONTENT", content_type: "application/pdf",
                    location: nil, headers: {})
    response = instance_double(status_class)
    allow(response).to receive(:is_a?).and_return(false)
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess)
            .and_return(status_class < Net::HTTPSuccess)
    allow(response).to receive(:is_a?).with(Net::HTTPRedirection)
            .and_return(status_class < Net::HTTPRedirection)
    allow(response).to receive(:body).and_return(body)
    allow(response).to receive(:code).and_return(status_class.name.match(/\d+/)&.to_s || "200")
    allow(response).to receive(:[]).with("content-type").and_return(content_type)
    allow(response).to receive(:[]).with("Location").and_return(location)
    allow(response).to receive(:[]).with("content-disposition").and_return(headers["content-disposition"])
    response
  end

  describe ".enabled?" do
    it "respects the env var" do
      ENV["SPARC_AUTHORITATIVE_FETCH_ENABLED"] = "false"
      expect(described_class).not_to be_enabled
      ENV["SPARC_AUTHORITATIVE_FETCH_ENABLED"] = "true"
      expect(described_class).to be_enabled
    end
  end

  describe ".call" do
    it "creates an Evidence record with the fetched body and links it" do
      success_class = Class.new(Net::HTTPSuccess) { class << self; def name; "Net::HTTPOK_200"; end; end }
      allow_any_instance_of(described_class).to receive(:follow_redirects)
        .and_return(stub_response(success_class))

      result = described_class.call(resource: resource, actor: actor)

      expect(result).to be_success
      expect(result.evidence).to be_persisted
      expect(result.evidence.file).to be_attached
      expect(resource.reload.evidence_id).to eq(result.evidence.id)
    end

    it "returns disabled when env var is off" do
      ENV["SPARC_AUTHORITATIVE_FETCH_ENABLED"] = "false"
      result = described_class.call(resource: resource, actor: actor)

      expect(result).not_to be_success
      expect(result.status_code).to eq(:service_unavailable)
    end

    it "rejects non-https hrefs" do
      resource.update!(href: "http://insecure.gov/policy.pdf")
      result = described_class.call(resource: resource, actor: actor)

      expect(result).not_to be_success
      expect(result.error).to match(/Only https:/i)
    end

    it "rejects when no href is set" do
      resource.update!(href: nil)
      result = described_class.call(resource: resource, actor: actor)

      expect(result).not_to be_success
      expect(result.error).to match(/no href/i)
    end

    it "returns a 502-style error on non-success HTTP response" do
      bad_class = Class.new(Net::HTTPClientError) { class << self; def name; "Net::HTTPNotFound_404"; end; end }
      allow_any_instance_of(described_class).to receive(:follow_redirects)
        .and_return(stub_response(bad_class))

      result = described_class.call(resource: resource, actor: actor)

      expect(result).not_to be_success
      expect(result.status_code).to eq(:bad_gateway)
    end

    it "rejects oversize bodies" do
      success_class = Class.new(Net::HTTPSuccess) { class << self; def name; "Net::HTTPOK_200"; end; end }
      huge = "x" * (described_class::MAX_BYTES + 1)
      allow_any_instance_of(described_class).to receive(:follow_redirects)
        .and_return(stub_response(success_class, body: huge))

      result = described_class.call(resource: resource, actor: actor)

      expect(result).not_to be_success
      expect(result.status_code).to eq(:payload_too_large)
    end

    it "translates network errors into a result, not an exception" do
      allow_any_instance_of(described_class).to receive(:follow_redirects)
        .and_raise(Net::OpenTimeout)

      result = described_class.call(resource: resource, actor: actor)
      expect(result).not_to be_success
      expect(result.error).to match(/Net::OpenTimeout/)
    end
  end
end
