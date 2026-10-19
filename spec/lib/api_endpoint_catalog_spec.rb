# frozen_string_literal: true

require "rails_helper"

# #1176 — the one definition of what an API token may be limited to.
RSpec.describe ApiEndpointCatalog do
  describe "the route inventory" do
    it "names every resource group, so a new one cannot reach the token form as a bare path fragment" do
      unlabeled = described_class.routes.map(&:group).uniq - described_class::GROUP_LABELS.keys

      expect(unlabeled).to be_empty,
        "add these /api/v1 groups to ApiEndpointCatalog::GROUP_LABELS: #{unlabeled.inspect}"
    end

    it "carries no label for a group that has no routes" do
      stale = described_class::GROUP_LABELS.keys - described_class.routes.map(&:group).uniq

      expect(stale).to be_empty, "these labelled groups have no routes: #{stale.inspect}"
    end

    it "lists as read-only only actions that are POST routes today" do
      post_keys = described_class.routes.select { |r| r.verb == "POST" }.map(&:key)

      expect(described_class::READ_ONLY_POSTS - post_keys).to be_empty
    end

    # The classification the owner chose: Read/Write per route, not per verb.
    it "classifies every route as read or write" do
      expect(described_class.routes.map(&:access).uniq).to contain_exactly("read", "write")
    end

    it "reads GET, and writes PUT, PATCH and DELETE" do
      described_class.routes.each do |route|
        case route.verb
        when "GET" then expect(route.access).to eq("read"), route.spec
        when "PUT", "PATCH", "DELETE" then expect(route.access).to eq("write"), route.spec
        end
      end
    end

    it "treats a POST that only computes as read, and one that creates as write" do
      by_key = described_class.routes.index_by(&:key)

      expect(by_key.fetch("api/v1/translations#sar_from_hdf").access).to eq("read")
      expect(by_key.fetch("api/v1/ssp_documents#import_fields_preview").access).to eq("read")
      # Both converts CREATE a document, whatever their name suggests.
      expect(by_key.fetch("api/v1/ssp_documents#convert").access).to eq("write")
      expect(by_key.fetch("api/v1/sar_documents#convert").access).to eq("write")
      expect(by_key.fetch("api/v1/ssp_documents#create").access).to eq("write")
    end

    it "groups nested resources under their parent's first path segment" do
      route = described_class.routes.find { |r| r.key == "api/v1/ssp_components#create" }

      expect(route.group).to eq("ssp_documents")
    end

    it "offers a group only the access levels its routes have" do
      oscal = described_class.groups.find { |g| g.key == "oscal" }
      ssp = described_class.groups.find { |g| g.key == "ssp_documents" }

      expect(oscal.access_levels).to eq([ "read" ])
      expect(ssp.access_levels).to eq(%w[read write])
    end
  end

  describe ".normalize" do
    it "stores All endpoints as an empty list, which has always meant unrestricted" do
      expect(described_class.normalize([ "ssp_documents:read", "*" ])).to eq([])
    end

    it "drops blanks and duplicates" do
      expect(described_class.normalize([ "", " ssp_documents:read ", "ssp_documents:read" ]))
        .to eq([ "ssp_documents:read" ])
    end
  end

  describe ".errors_for" do
    it "accepts known groups, levels, and path patterns that reach a route" do
      expect(described_class.errors_for([ "ssp_documents:read", "oscal:read", "/api/v1/ksi_*",
                                          "/api/v1/ssp_documents/5", "/api/v1/ssp_documents/5/components*" ]))
        .to be_empty
    end

    it "refuses an unknown group" do
      expect(described_class.errors_for([ "nope:read" ])).to contain_exactly(a_string_including("not an API resource group"))
    end

    it "refuses a level the group does not have" do
      expect(described_class.errors_for([ "oscal:write" ])).to contain_exactly(a_string_including("not \"write\""))
    end

    it "refuses a path pattern that matches no route" do
      expect(described_class.errors_for([ "/api/v1/zzz*", "/api/v1/ssp_documents/5/nothing" ]))
        .to contain_exactly(a_string_including("/api/v1/zzz*"), a_string_including("/api/v1/ssp_documents/5/nothing"))
    end
  end

  describe ".permits?" do
    def permits?(entries, path, verb, key)
      described_class.permits?(entries, path: path, verb: verb, route_key: key)
    end

    it "lets everything through with no limits" do
      expect(permits?([], "/api/v1/users", "DELETE", "api/v1/users#destroy")).to be true
    end

    it "lets Read fetch, and stops it writing" do
      expect(permits?([ "ssp_documents:read" ], "/api/v1/ssp_documents/5", "GET", "api/v1/ssp_documents#show")).to be true
      expect(permits?([ "ssp_documents:read" ], "/api/v1/ssp_documents/5", "PATCH", "api/v1/ssp_documents#update")).to be false
    end

    it "lets Write change, and stops it reading" do
      expect(permits?([ "ssp_documents:write" ], "/api/v1/ssp_documents/5", "PATCH", "api/v1/ssp_documents#update")).to be true
      expect(permits?([ "ssp_documents:write" ], "/api/v1/ssp_documents/5", "GET", "api/v1/ssp_documents#show")).to be false
    end

    it "lets Read run a POST that only computes, and not one that creates" do
      expect(permits?([ "oscal:read" ], "/api/v1/oscal/sar_from_hdf", "POST", "api/v1/translations#sar_from_hdf")).to be true
      expect(permits?([ "ssp_documents:read" ], "/api/v1/ssp_documents/convert", "POST", "api/v1/ssp_documents#convert")).to be false
    end

    it "keeps a group's limit to that group" do
      expect(permits?([ "ssp_documents:read" ], "/api/v1/sar_documents", "GET", "api/v1/sar_documents#index")).to be false
    end

    it "keeps a pre-#1176 path pattern working as Read and Write on its paths" do
      expect(permits?([ "/api/v1/ssp_documents*" ], "/api/v1/ssp_documents/5", "DELETE", "api/v1/ssp_documents#destroy")).to be true
      expect(permits?([ "/api/v1/ssp_documents*" ], "/api/v1/sar_documents", "GET", "api/v1/sar_documents#index")).to be false
      expect(permits?([ "/api/v1/available" ], "/api/v1/available", "GET", "api/v1/discovery#available")).to be true
      expect(permits?([ "/api/v1/available" ], "/api/v1/available/x", "GET", "api/v1/discovery#available")).to be false
    end
  end

  describe ".describe" do
    it "reads as the screens show it" do
      expect(described_class.describe([])).to eq([ "All endpoints" ])
      expect(described_class.describe([ "ssp_documents:write", "ssp_documents:read", "/api/v1/evidences" ]))
        .to eq([ "System security plans (SSP): Read + Write", "/api/v1/evidences (path pattern: Read + Write)" ])
    end
  end
end
