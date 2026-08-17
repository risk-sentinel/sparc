# frozen_string_literal: true

# #888 — the card slots for each collection.
#
# The card partial is deliberately generic; deciding what a *system security
# plan* puts in it is a per-resource judgement, and that judgement belongs
# somewhere reviewable rather than spread across seventeen ERB files. Keeping it
# here also means the answer to "why does this card show controls but that one
# shows regions" is one file, not a hunt.
#
# The rule each builder follows: a card must answer what the thing is, what
# state it is in, and how big it is — without the reader opening it. Fields that
# only matter once you are inside stay inside.
module CollectionCardHelper
  # The four artifact documents (SSP, SAR, SAP, POA&M) share a shape: a
  # lifecycle, a parse status, a version, a control or item count. Their
  # differences are the count's name and whether OSCAL enrichment applies.
  def document_card_slots(doc, count:, count_label:, version: nil, enriched: nil)
    {
      title: doc.name.presence || "Untitled",
      badges: document_card_badges(doc, enriched: enriched),
      description: doc.description,
      metrics: [
        { value: count, label: count_label },
        ({ value: version, label: "version" } if version.present?)
      ].compact,
      chips: document_card_chips(doc),
      footer: "Created #{doc.created_at.strftime('%Y-%m-%d')}"
    }
  end

  # Parse status and lifecycle answer different questions — "did the import
  # work" and "is this approved" — so a document mid-import shows the former and
  # a settled one the latter, exactly as the table does.
  def document_card_badges(doc, enriched: nil)
    badges = []

    if doc.respond_to?(:processing?) && (doc.processing? || doc.pending? || doc.failed?)
      badges << { text: doc.status,
                  class: "#{doc.failed? ? 'badge-fail' : 'badge-warn'} rounded fw-semibold" }
    elsif doc.respond_to?(:lifecycle_label)
      badges << { text: doc.lifecycle_label, class: "#{doc.lifecycle_badge_class} rounded fw-semibold" }
    end

    unless enriched.nil?
      badges << { text: enriched ? "Enriched" : "Basic",
                  class: enriched ? "sparc-oscal-enriched" : "sparc-oscal-basic" }
    end

    badges
  end

  # #627/#628 — content-completeness is not the same as parse status: a
  # metadata-only document parses fine and is still not finishable. The table
  # flags it, so the card must too.
  def document_card_chips(doc)
    chips = []

    if doc.respond_to?(:content_complete?) && doc.respond_to?(:published_lifecycle?) &&
       !doc.published_lifecycle? && !doc.content_complete?
      chips << { text: "Incomplete", class: "sparc-chip--warn",
                 title: doc.content_completeness_gaps.join("; ") }
    end

    chips
  end

  # How a document got here changes how much to trust its structure, so it is
  # worth a chip rather than a column a reader has to go looking for.
  # #946 — say what the document's origin actually was, or say nothing.
  #
  # The `else` branch used to render "Import" with spreadsheet styling for
  # EVERYTHING that was not wizard or oscal_import — so a profile-generated SSP
  # and an SSP-generated SAR both displayed as spreadsheet imports, and a
  # document with no recorded method displayed as one too. That is the same
  # false provenance the `creation_method` column default was making, one layer
  # up: `default: "excel"` was dropped precisely so an unknown origin stops
  # claiming to be a spreadsheet, and a view that fills the gap back in would
  # undo it.
  CREATION_METHOD_BADGES = {
    "wizard"       => { text: "Wizard",   class: "sparc-source-badge sparc-source-wizard" },
    "oscal_import" => { text: "OSCAL",    class: "sparc-source-badge sparc-source-oscal" },
    "excel"        => { text: "Import",   class: "sparc-source-badge sparc-source-excel" },
    "profile"      => { text: "Profile",  class: "sparc-source-badge sparc-source-profile" },
    "ssp"          => { text: "From SSP", class: "sparc-source-badge sparc-source-profile" }
  }.freeze

  def creation_method_badge(doc)
    CREATION_METHOD_BADGES[doc.try(:creation_method).to_s]
  end

  # Truncation belongs here rather than in CSS when the value is a single long
  # token (a URL, an OSCAL uuid) that would otherwise blow out the grid column.
  def card_short(value, length: 60)
    value.to_s.truncate(length)
  end
end
