# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# #868 — evidence upload guards.
#
# The defect this covers: the web UI accepted files the API rejected. The API
# ran an executable-signature check; EvidencesController ran nothing at all, so
# an .exe or a shell script could be stored as evidence through the browser.
# There was also no server-side extension allowlist anywhere — the 14 advertised
# types were an `accept` attribute and some client-side JS, both of which a
# direct POST ignores.
#
# So every rejection case is asserted against BOTH paths. A guard that holds on
# one and not the other is the bug, not a partial fix.
RSpec.describe "Evidence upload policy (#868)", type: :request do
  let(:user) { create(:user, admin: true) }
  let(:boundary) { create(:authorization_boundary) }

  around do |example|
    Dir.mktmpdir("evidence-upload-") { |dir| @dir = dir; example.run }
  end

  # Bytes first, name second — that is the whole point of the content check.
  def upload(name, bytes, content_type = "application/octet-stream")
    path = File.join(@dir, name)
    File.binwrite(path, bytes)
    Rack::Test::UploadedFile.new(path, content_type, original_filename: name)
  end

  def metadata
    {
      title: "Upload guard fixture",
      description: "Fixture for #868",
      evidence_type: "artifact",
      status: "collected",
      source: "spec",
      authorization_boundary_id: boundary.id,
      # #947 — evidence must support at least one control.
      control_ids: "ac-2"
    }
  end

  def post_ui(file)
    post evidences_path, params: { evidence: metadata.merge(file: file) }
  end

  def post_api(file)
    post "/api/v1/evidences",
         params: { evidence: metadata.merge(file: file) },
         headers: { "Authorization" => "Bearer #{@token}" }
  end

  before do
    sign_in_as(user)
    @token = ApiToken.generate!(user: user, name: "evidence-upload-spec").plaintext_token
  end

  # Each case: a file that must be refused, and why.
  {
    "a Linux ELF binary renamed to .pdf" => {
      file: [ "report.pdf", "\x7fELF\x02\x01\x01\x00rest of the binary" ],
      because: /ELF|executable/i
    },
    "a Windows PE executable renamed to .png" => {
      file: [ "screenshot.png", "MZ\x90\x00\x03\x00\x00\x00" ],
      because: /PE|MS-DOS|executable/i
    },
    "a shell script renamed to .log" => {
      file: [ "audit.log", "#!/bin/sh\nrm -rf /\n" ],
      because: /shebang|script|executable/i
    },
    "an archive, which hides its contents from every check" => {
      file: [ "evidence.zip", "PK\x03\x04rest" ],
      because: /not an accepted evidence type/i
    },
    "an executable with no extension at all" => {
      file: [ "payload", "\x7fELF\x02\x01\x01\x00" ],
      because: /no file extension/i
    },
    "a file whose bytes contradict its extension" => {
      file: [ "report.pdf", "this is plainly not a pdf" ],
      because: /contents are|must match/i
    }
  }.each do |scenario, spec|
    name, bytes = spec[:file]

    it "rejects #{scenario} — web UI" do
      expect { post_ui(upload(name, bytes)) }.not_to change(Evidence, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:error] || response.body).to match(spec[:because])
    end

    it "rejects #{scenario} — API" do
      expect { post_api(upload(name, bytes)) }.not_to change(Evidence, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to match(spec[:because])
    end
  end

  describe "legitimate evidence still uploads" do
    it "accepts a real PDF through the web UI" do
      file = upload("policy.pdf", "%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n%%EOF\n", "application/pdf")

      expect { post_ui(file) }.to change(Evidence, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end

    it "accepts a real PDF through the API" do
      file = upload("policy.pdf", "%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n%%EOF\n", "application/pdf")

      expect { post_api(file) }.to change(Evidence, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it "accepts a plain-text log" do
      file = upload("scan.log", "2026-07-30 INFO scan completed\n", "text/plain")

      expect { post_ui(file) }.to change(Evidence, :count).by(1)
    end

    # #902 — this used to assert on flash[:notice], and passed, while the user
    # saw nothing at all: the layout rendered success/error/warning only, so
    # `notice` was set and silently dropped on the floor. A spec that asserts a
    # controller set a value proves nothing about whether anyone can read it —
    # hence the rendering coverage in spec/requests/flash_rendering_spec.rb.
    it "confirms the file landed, naming it and its checksum" do
      file = upload("policy.pdf", "%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n%%EOF\n", "application/pdf")
      post_ui(file)

      expect(flash[:success]).to include("policy.pdf")
      expect(flash[:success]).to match(/SHA-256/i)
    end
  end

  describe "collecting several artefacts in a run (#868)" do
    let(:pdf) { upload("policy.pdf", "%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n%%EOF\n", "application/pdf") }

    it "returns to the form when 'Save and add another' is used" do
      post evidences_path, params: {
        evidence: metadata.merge(file: pdf), commit_and_new: "Save and add another"
      }

      expect(response).to redirect_to(
        new_evidence_path(authorization_boundary_id: boundary.id, evidence_type: "artifact")
      )
    end

    it "carries the boundary and type forward so they need not be re-picked" do
      get new_evidence_path(authorization_boundary_id: boundary.id, evidence_type: "screenshot")

      expect(response).to have_http_status(:ok)

      # Assert on what the user actually sees pre-selected, not on ivars.
      doc = Nokogiri::HTML(response.body)
      selected = doc.css("select option[selected]").map { |o| o["value"] }
      expect(selected).to include("screenshot")
      expect(selected).to include(boundary.id.to_s)
    end

    it "still lands on the record when the normal save is used" do
      post evidences_path, params: { evidence: metadata.merge(file: pdf) }

      expect(response).to redirect_to(Evidence.order(:created_at).last)
    end

    it "keeps the typed metadata when a file is rejected" do
      post evidences_path, params: {
        evidence: metadata.merge(title: "Kept on rejection", file: upload("x.pdf", "\x7fELF\x02"))
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Kept on rejection")
    end
  end

  describe "the advertised list and the enforced list" do
    it "are generated from the same constant" do
      advertised = EvidenceUploadPolicy.accept_attribute.split(",")

      expect(advertised).to match_array(EvidenceUploadPolicy::ALLOWED_EXTENSIONS)
    end

    it "does not accept archives" do
      expect(EvidenceUploadPolicy::ALLOWED_EXTENSIONS).not_to include(".zip")
    end
  end
end
