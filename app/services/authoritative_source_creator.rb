# Creates a standalone authoritative-source library entry (#646).
#
# Any authenticated actor may add a source. It is created org/boundary-scoped
# by default (source = "managed", globally_available = false, organization set
# to the actor's first org). When `instance_wide` is requested, availability is
# routed through the existing promotion approval (BackMatterResourcePromotionService):
# actors with promotion authority self-approve to instance-wide immediately;
# everyone else's request lands in the promotion queue. Nothing here grants
# instance-wide availability without that gate.
#
# Shared by the web AuthoritativeSourcesController and the API so the UI is a
# thin client over the same logic (API-first).
class AuthoritativeSourceCreator
  Result = Struct.new(:success, :resource, :message, :error, keyword_init: true) do
    def success? = success
  end

  def self.call(...) = new(...).call

  def initialize(actor:, attrs:, instance_wide: false)
    @actor        = actor
    @attrs        = attrs
    @instance_wide = ActiveModel::Type::Boolean.new.cast(instance_wide)
  end

  def call
    resource = BackMatterResource.new(@attrs)
    resource.uuid               = SecureRandom.uuid if resource.uuid.blank?
    resource.source             = "managed"
    resource.resourceable       = nil # standalone library entry
    resource.organization       = @actor.organizations.first
    resource.globally_available = false # default: org/boundary-scoped

    unless resource.save
      return Result.new(success: false, resource: resource,
                        error: resource.errors.full_messages.to_sentence)
    end

    Result.new(success: true, resource: resource, message: finalize(resource))
  end

  private

  # Returns a short, human-readable availability descriptor.
  def finalize(resource)
    return "available to your organization/boundary" unless @instance_wide

    service = BackMatterResourcePromotionService.new(resource: resource, actor: @actor)
    service.request_promotion!

    if service.can_approve?
      service.approve! # flips to authoritative + globally_available, audit-logged
      "promoted to instance-wide"
    else
      "submitted for instance-wide approval"
    end
  end
end
