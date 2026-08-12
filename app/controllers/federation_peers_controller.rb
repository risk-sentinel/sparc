# NC/LC admin UI for federation peers (#372). Admin-only — full CRUD
# plus a sync trigger. service_token and signing_secret are write-only
# fields on the form; blank submissions on edit leave them unchanged.
class FederationPeersController < ApplicationController
  include CollectionViewable
  before_action :require_admin
  before_action :set_peer, only: %i[show edit update destroy sync]

  def index
    # #888 — no search here before. A peer is recalled by its URL as often as
    # by its name, which is why FederationPeer declares both searchable.
    scope = FederationPeer.order(:name).search_text(params[:q])

    @view_mode = resolve_view_mode(:federation_peers)
    @pagy, @peers = paginate_collection(scope)
  end

  def show
    @recent_imports = BackMatterResource.where(federated_from_instance: @peer.base_url)
                                        .order(federated_at: :desc)
                                        .limit(25)
  end

  def new
    @peer = FederationPeer.new
  end

  def edit
    # Empty action: renders edit.html.erb; the record is loaded by a set_* before_action.
  end

  def create
    @peer = FederationPeer.new(public_attrs)
    apply_secrets(@peer)

    if @peer.save
      audit_log("federation_peer_created", subject: @peer,
                metadata: { name: @peer.name, base_url: @peer.base_url })
      flash[:success] = "Federation peer \"#{@peer.name}\" added"
      redirect_to federation_peer_path(@peer)
    else
      flash.now[:error] = @peer.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @peer.assign_attributes(public_attrs)
    apply_secrets(@peer)

    if @peer.save
      audit_log("federation_peer_updated", subject: @peer, metadata: { name: @peer.name })
      flash[:success] = "Federation peer \"#{@peer.name}\" updated"
      redirect_to federation_peer_path(@peer)
    else
      flash.now[:error] = @peer.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    audit_log("federation_peer_deleted", subject: @peer, metadata: { name: @peer.name })
    @peer.destroy
    flash[:success] = "Federation peer removed"
    redirect_to federation_peers_path
  end

  def sync
    result = AuthoritativeSourceFederationService.pull(peer: @peer, actor: current_user)
    if result.success?
      flash[:success] = "Pulled #{result.imported.size} new resource(s) from #{@peer.name} " \
                        "(#{result.skipped.size} skipped)"
    else
      flash[:error] = "Sync failed: #{result.error}"
    end
    redirect_to federation_peer_path(@peer)
  end

  private

  def set_peer
    @peer = FederationPeer.find(params[:id])
  end

  def public_attrs
    params.require(:federation_peer).permit(:name, :base_url, :enabled)
  end

  def apply_secrets(peer)
    nested = params.fetch(:federation_peer, {})
    peer.service_token  = nested[:service_token]  if nested[:service_token].present?
    peer.signing_secret = nested[:signing_secret] if nested[:signing_secret].present?
  end

  # #919 — was a hand-rolled admin gate, which disagreed with
  # Api::V1::FederationPeersController's `back_matter.federate` check: the same
  # operation had two different answers depending on the surface.
  #
  # Now the permission, matching the API. The seeds grant back_matter.federate to
  # policy_manager (federation is instance-level governance, not a boundary act),
  # so this widens web access from admin-only to admin + policy team — which is
  # the posture decided for instance-tier back-matter, and what the API already
  # allowed.
  #
  # authorize_permission! rather than a bespoke redirect: it honours
  # SparcConfig.any_auth_enabled? and emits the authorization_failure audit event
  # (AU-2), neither of which the hand-rolled version did.
  def require_admin
    authorize_permission!("back_matter.federate")
  end
end
