# frozen_string_literal: true

# 1.18.0-rf #1293 — how many of each document type a user sees, within one
# boundary or across everything they can reach.
#
# The navigation shows these beside each list link. A count that disagreed with
# the list it opens would promise records that are not there, or reveal records
# the user cannot open, so each count is taken from the SAME relation the list
# draws:
#
#   SSP, SAP, SAR, Evidence, POA&M  the list controller's own boundary_scoped
#                                   declaration (BoundaryScopedDocument.index_relation),
#                                   the definition the homepage counts with (#1243)
#   CDEFs                           every CDEF, as the CDEF list shows
#
# narrowed by BoundaryScopedList, the rule the lists, the sidebar and Api::V1
# share. No boundary (nil) counts everything the user can reach (owner, #1287).
#
# One COUNT per type: a fixed number of queries however many boundaries or
# documents there are. Callers memoize per request.
#
# NIST SP 800-53 Rev 5:
#   AC-3 Access Enforcement — counts only what the user may list.
#   AC-4 Information Flow Enforcement — never another boundary's records.
class BoundaryNavCounts
  # In sidebar order.
  LISTS = {
    cdef:     nil,
    ssp:      "SspDocumentsController",
    sap:      "SapDocumentsController",
    evidence: "EvidencesController",
    sar:      "SarDocumentsController",
    poam:     "PoamDocumentsController"
  }.freeze

  def self.for(boundary, user)
    new(boundary, user).counts
  end

  def initialize(boundary, user)
    @boundary = boundary
    @user = user
  end

  # { cdef: 3, ssp: 1, ... }
  def counts
    LISTS.to_h { |type, controller| [ type, relation(type, controller).count ] }
  end

  private

  def relation(type, controller)
    base = controller ? BoundaryScopedDocument.index_relation(controller.constantize, @user) : CdefDocument.all
    BoundaryScopedList.narrow(type, base, @boundary&.id)
  end
end
