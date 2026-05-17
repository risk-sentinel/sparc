require "rails_helper"

RSpec.describe AwsLabsCdefSourceClient do
  let(:repo)   { "awslabs/oscal-content-for-aws-services" }
  let(:branch) { "main" }
  let(:client) { described_class.new(repo: repo, branch: branch, token: nil) }

  # A minimal Net::HTTPResponse stand-in. We can't easily instantiate the
  # real class without invoking the HTTP machinery, so we use a struct that
  # quacks like one for the parts we touch (code, body, [], etag header).
  StubResponse = Struct.new(:code, :body, :headers) do
    def [](k) = headers[k.downcase] || headers[k]
  end

  def stub_get(response)
    fake_http = double("Net::HTTP")
    allow(Net::HTTP).to receive(:start).and_yield(fake_http)
    allow(fake_http).to receive(:read_timeout=)
    allow(fake_http).to receive(:open_timeout=)
    allow(fake_http).to receive(:request).and_return(response)
  end

  describe "#list_component_definition_files" do
    it "returns blob entries under component-definitions/ ending in .json" do
      body = {
        "tree" => [
          { "type" => "blob", "path" => "component-definitions/s3/s3-cd.json", "sha" => "aaa" },
          { "type" => "blob", "path" => "component-definitions/ec2/README.md", "sha" => "bbb" },
          { "type" => "tree", "path" => "component-definitions/s3", "sha" => "ccc" },
          { "type" => "blob", "path" => "component-definitions/iam/iam-cd.json", "sha" => "ddd" }
        ]
      }.to_json

      stub_get(StubResponse.new("200", body, { "etag" => 'W/"abc"' }))

      files = client.list_component_definition_files
      expect(files.length).to eq(2)
      expect(files.map { |f| f["path"] }).to contain_exactly(
        "component-definitions/s3/s3-cd.json",
        "component-definitions/iam/iam-cd.json"
      )
    end

    it "returns nil and logs when the server reports 304 Not Modified" do
      Rails.cache.write("aws_labs_cdef:etag:tree:#{repo}:#{branch}", 'W/"abc"')
      stub_get(StubResponse.new("304", "", {}))

      expect(client.list_component_definition_files).to be_nil
    end

    it "raises RateLimitedError on 403" do
      stub_get(StubResponse.new("403", "rate limited", {}))
      expect { client.list_component_definition_files }.to raise_error(described_class::RateLimitedError)
    end

    it "raises NotFoundError on 404" do
      stub_get(StubResponse.new("404", "not found", {}))
      expect { client.list_component_definition_files }.to raise_error(described_class::NotFoundError)
    end
  end

  describe "#fetch_file" do
    it "decodes base64 content and returns provenance fields" do
      body = {
        "path" => "component-definitions/s3/s3-cd.json",
        "sha" => "abc123",
        "html_url" => "https://github.com/awslabs/oscal-content-for-aws-services/blob/main/component-definitions/s3/s3-cd.json",
        "encoding" => "base64",
        "content" => Base64.strict_encode64('{"component-definition":{}}')
      }.to_json
      stub_get(StubResponse.new("200", body, {}))

      file = client.fetch_file(path: "component-definitions/s3/s3-cd.json")
      expect(file[:sha]).to eq("abc123")
      expect(file[:content]).to eq('{"component-definition":{}}')
      expect(file[:html_url]).to include("github.com")
    end
  end
end
