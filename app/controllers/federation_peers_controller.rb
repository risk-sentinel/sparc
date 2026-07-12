# NC/LC admin UI for federation peers (#372). Admin-only — full CRUD
# plus a sync trigger. service_token and signing_secret are write-only
# fields on the form; blank submissions on edit leave them unchanged.
class FederationPeersController < ApplicationController
  before_action :require_admin
  before_action :set_peer, only: %i[show edit update destroy sync]

  def index
    @peers = FederationPeer.order(:name)
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

  def require_admin
    return if current_user&.admin?

    flash[:error] = "Federation peer administration is restricted to instance admins"
    redirect_to root_path
  end
end
