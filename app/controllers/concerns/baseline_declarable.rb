# frozen_string_literal: true

# Declaring a document's baseline from the UI (#911, layer 2 of 3).
#
# The reconciliation gate refuses to update a document that cannot name the
# catalog its controls descend from. That refusal is only fair if the remedy is
# reachable — otherwise a legacy document becomes permanently uneditable and the
# gate is a trap rather than a prompt.
#
# Before this, it was a trap for three of the six types. `profile_document_id`
# was reachable on an SSP only through the CREATION wizard, and the CDEF and
# profile controllers never referenced their lineage FK at all. SAR and SAP
# already had `associate_source`; this generalises that idea to every type so
# the banner's "Set baseline" control has somewhere to post.
#
# **SPARC never synthesises a profile from the document's own controls.** The
# picker offers what is loaded. Where nothing suitable exists, the honest answer
# is that the user must load the right profile or catalog first — inventing one
# from the document being validated would manufacture a baseline out of the very
# thing it is supposed to check.
module BaselineDeclarable
  extend ActiveSupport::Concern

  # PATCH /<documents>/:id/set_baseline
  #
  # Deliberately NOT gated: this is the write the gate exists to provoke.
  def set_baseline
    document = baseline_document
    permitted = params.require(document.model_name.param_key).permit(
      *document.class.lineage_attribute_names
    )

    if permitted.values.all?(&:blank?)
      redirect_back fallback_location: document,
                    alert: "Choose a baseline — nothing was selected."
      return
    end

    if document.rebaselining_published?(permitted)
      redirect_back fallback_location: document,
                    alert: "This #{document.model_name.human.downcase} is published and its " \
                           "baseline is fixed. Create a copy to point at a different baseline."
      return
    end

    document.update!(permitted)
    audit_log("#{document.model_name.element}_baseline_declared", subject: document,
              metadata: permitted.to_h)

    redirect_back fallback_location: document,
                  notice: "Baseline set. This document's controls can now be traced to a catalog."
  end

  private

  # The instance variable each controller already sets in its own `set_*`
  # before_action (`@ssp_document`, `@cdef_document`, ...).
  def baseline_document
    instance_variable_get(:"@#{controller_name.singularize}")
  end

  # #928 — the rule itself lives on CatalogLineage, because the API reaches the
  # same write through `PATCH /api/v1/<documents>/:id` and a controller-side
  # check would have covered only this surface.
  #
  # `set_baseline` stays outside `ensure_editable!` deliberately: a document
  # published before #911 shipped can be both published AND unreconciled, and
  # blocking it wholesale would make those permanently unreconcilable. The rule
  # is about the CHANGE, not the state — see CatalogLineage#rebaselining_published?.
end
