# Join model linking any control type to a BackMatterResource.
#
# Supports polymorphic control types: CatalogControl, CdefControl,
# ProfileControl, SspControl, SarControl, SapControl.
#
# NIST SA-10: Developer Configuration Management
class ControlBackMatterLink < ApplicationRecord
  belongs_to :linkable, polymorphic: true
  belongs_to :back_matter_resource

  validates :back_matter_resource_id,
            uniqueness: { scope: [ :linkable_type, :linkable_id ],
                          message: "is already linked to this control" }
end
