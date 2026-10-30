# #887 — presentation for the CDEF browser card.
#
# Kept out of the view so the decisions here — what counts as "coverage", how
# a derived value is distinguished from an asserted one — are testable without
# rendering, and so #888 can reuse the same shapes on other screens.
module CdefBrowserHelper
  # The AWS importer bakes the OSCAL version into the stored name
  # ("AWS xray.oscal (oscal 1.2.1)"), and the card also shows it as a badge —
  # so the title repeated it. Stripped for DISPLAY only: the name is what slugs
  # and existing links were derived from, so changing the stored value would
  # move every URL.
  #
  # Anchored at the end and matched only against a version-shaped suffix, so a
  # custom name that happens to contain parentheses is left alone.
  OSCAL_VERSION_SUFFIX = /\s\(oscal\s[0-9]+(?:\.[0-9]+)*\)\z/i

  def cdef_display_name(document)
    document.name.to_s.sub(OSCAL_VERSION_SUFFIX, "")
  end

  # Where the content came from. The UI must never blur upstream AWS content
  # (Apache-2.0, explicitly labelled experimental) with SPARC-curated or
  # org-provided definitions, because they carry different warranties.
  # 1.18.0-rf #1300 — through CdefDocument#source_kind, the definition the
  # list's source tabs and filter use.
  def cdef_source_badge(document)
    case document.source_kind
    when "aws"   then { text: "AWS", class: "sparc-status sparc-status--warning", title: "Upstream AWS Labs content" }
    when "org"   then { text: "Org", class: "badge badge-info", title: "Organization-provided" }
    when "sparc" then { text: "SPARC", class: "badge bg-primary", title: "Generated from a SPARC profile" }
    else              { text: "Local", class: "badge bg-secondary", title: "Uploaded or hand-authored" }
    end
  end

  # 1.18.0-rf #1300 — where it came from, which version, and when it last
  # changed: the AWS Labs sync for upstream content, else the last edit.
  def cdef_source_line(document)
    version = document.cdef_version.presence && "v#{document.cdef_version}"
    if document.source_kind == "aws"
      fetched = document.import_metadata["fetched_at"].presence && Time.zone.parse(document.import_metadata["fetched_at"].to_s)
      [ "awslabs/oscal-content", version, (fetched && "synced #{time_ago_in_words(fetched)} ago") ]
    else
      origin = document.source_kind == "org" ? (document.organization&.name || "Organization") : CdefDocument::SOURCES[document.source_kind]
      [ origin, version, "edited #{time_ago_in_words(document.updated_at)} ago" ]
    end.compact.join(" · ")
  rescue ArgumentError
    [ "awslabs/oscal-content", version ].compact.join(" · ")
  end

  # 1.18.0-rf #1300 — the CDEF card and row under SPARC_NAV_SHELL: source and
  # last change, what it applies to, the controls it covers and their
  # families, SPARC's enrichment of upstream content, and — when the list is
  # filtered to a boundary with a baseline — coverage of that baseline.
  FAMILY_CHIPS_SHOWN = 8

  def cdef_shell_slots(document, summary, facts, coverage)
    families = facts[:families]
    family_chips = families.first(FAMILY_CHIPS_SHOWN).map { { text: _1, class: "sparc-chip--family", title: "Control family" } }
    if families.size > FAMILY_CHIPS_SHOWN
      family_chips << { text: "+#{families.size - FAMILY_CHIPS_SHOWN}", class: "sparc-chip--family",
                        title: families.drop(FAMILY_CHIPS_SHOWN).join(", ") }
    end
    enrichment = if document.source_kind == "aws" && summary[:enriched_control_count].positive?
      [ { text: "SPARC enrichment", class: "sparc-chip--derived",
          title: "#{summary[:enriched_control_count]} NIST controls mapped by SPARC" } ]
    else
      []
    end
    applies = summary[:component_types].presence && "Applies to #{summary[:component_types].map(&:humanize).join(', ').downcase}"
    {
      metrics: [
        { value: summary[:service_count], label: "services".pluralize(summary[:service_count]) },
        *cdef_listing_metrics(facts, coverage),
        { value: summary[:check_count], label: "checks" }
      ],
      chips: enrichment + family_chips + cdef_card_chips(summary),
      footer: [ cdef_source_line(document), applies, cdef_mapping_note(summary) ].compact.join(" · "),
      meter: coverage && { value: coverage[:pct], label: "#{coverage[:pct].round}% of the boundary's baseline covered" }
    }
  end

  # The numbers a CDEF row adds (#1300): controls covered, and against the
  # boundary's baseline when the list is filtered to a boundary that has one.
  def cdef_listing_metrics(facts, coverage)
    metrics = [ { value: facts[:controls], label: "controls covered" } ]
    if coverage
      metrics << { value: "#{coverage[:pct].round}%", label: "of the boundary's baseline (#{coverage[:covered]}/#{coverage[:total]})" }
    end
    metrics
  end

  # The numbers worth comparing between two CDEFs at a glance.
  #
  # "services", not "components": an upstream file is a service family, and
  # the OSCAL component count would include every Config Rule too (s3.oscal is
  # 1 service and 20 rules). Counting rules as components made a card read as
  # though the definition covered 21 things.
  def cdef_card_metrics(document, summary)
    [
      { value: summary[:service_count], label: "services".pluralize(summary[:service_count]) },
      { value: summary[:native_control_count], label: "controls" },
      { value: summary[:check_count], label: "checks" },
      { value: document.cdef_controls.size, label: "requirements" }
    ]
  end

  # What the definition actually covers. A card headed "AWS workspaces.oscal"
  # tells you nothing; naming the four services inside it does.
  def cdef_service_summary(summary, limit: 3)
    titles = summary[:service_titles]
    return nil if titles.empty?

    shown = titles.first(limit).join(", ")
    titles.size > limit ? "#{shown} +#{titles.size - limit} more" : shown
  end

  # The applicability chips are a union across every service in the file. When
  # those services do not share a partition set, say so — otherwise a card can
  # show `aws-us-gov` because one of four services is in GovCloud, and a
  # FedRAMP user would reasonably read that as applying to the whole thing.
  def cdef_partition_caveat(summary)
    return nil if summary[:partitions_uniform]

    "Availability varies by service — see the detail view."
  end

  # Applicability and capability, as chips.
  #
  # Ordering is deliberate: partition first, because for a FedRAMP or agency
  # user that is the first question asked of any component — GovCloud or not.
  def cdef_card_chips(summary)
    chips = []

    # One chip per partition, named rather than identified. `aws-cn` makes the
    # reader decode a string; "AWS China" just says it. The raw ids stay in the
    # data and remain searchable — this is a display concern only.
    summary[:partitions].each do |partition|
      chips << {
        text: CdefComponent.partition_label(partition),
        title: "Available in the #{partition} partition"
      }
    end

    summary[:availability].each { |scope| chips << { text: scope, title: "Deployment scope" } }

    summary[:lifecycle_stages].reject { |s| s == "generally-available" }.each do |stage|
      # Only non-GA is worth surfacing — flagging every GA service as GA is noise.
      chips << { text: stage.tr("-", " "), class: "sparc-chip--warn", title: "Lifecycle stage" }
    end

    chips << { text: "automated checks", title: "Carries Config Rules or other check bindings" } if summary[:check_count].positive?

    summary[:declared_capabilities].each do |capability|
      chips << { text: capability, class: "sparc-chip--strong", title: "Declared by the component author" }
    end

    # Derived capabilities render dashed and italic — an inference must not
    # carry the same visual weight as the author's own assertion.
    summary[:derived_capabilities].each do |capability|
      chips << { text: capability, class: "sparc-chip--derived", title: "Derived by SPARC from control coverage" }
    end

    chips
  end

  # 163 of the 230 upstream AWS CDEFs assert no control coverage. Rendering an
  # empty region for the majority of the corpus would read as a broken screen,
  # so the state is stated — and the two ways of having "nothing" are
  # distinguished, because they mean different things.
  def cdef_coverage_note(summary)
    return nil if summary[:native_control_count].positive?

    if summary[:enriched_control_count].positive?
      "No control coverage asserted upstream — #{summary[:enriched_control_count]} derived by SPARC."
    elsif summary[:component_count].zero?
      "Not yet indexed."
    else
      "No control coverage asserted."
    end
  end

  # `aws_direct` is a one-hop Security Hub lookup; `via_config_rule` goes
  # through the Config Rule. Reported as direct vs inferred, never as a score —
  # the importer records no confidence value and inventing one would fabricate
  # precision the data does not have.
  def cdef_mapping_note(summary)
    sources = summary[:mapping_sources]
    return nil if sources.empty?

    sources.include?("aws_direct") ? "direct mapping" : "inferred via Config Rule"
  end
end
