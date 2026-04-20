# Background job that propagates AuthorizationBoundary metadata to all
# linked documents. Enqueued from AuthorizationBoundariesController#update
# whenever boundary_metadata or profile_document_id changes (#395 P3).
#
class BoundaryMetadataSyncJob < ApplicationJob
  queue_as :default

  def perform(boundary_id)
    boundary = AuthorizationBoundary.find_by(id: boundary_id)
    return unless boundary
    BoundaryMetadataSyncService.new(boundary).propagate!
  end
end
