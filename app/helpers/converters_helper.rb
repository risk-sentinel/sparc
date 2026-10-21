# frozen_string_literal: true

module ConvertersHelper
  def converter_status_color(status)
    case status
    when "complete"    then "success"
    when "draft"       then "warning"
    when "deprecated"  then "secondary"
    when "processing"  then "info"
    when "failed"      then "danger"
    else "light"
    end
  end

  def converter_type_color(converter_type)
    case converter_type
    when "cci_to_nist"              then ApplicationHelper::COLOR_RED
    when "cis_to_nist"              then ApplicationHelper::COLOR_BLUE
    when "scap_oval_to_nist"        then ApplicationHelper::COLOR_EMERALD
    when "aws_config_to_nist"       then "#ff9900"  # AWS orange
    when "aws_security_hub_to_nist" then "#ec7211"  # AWS Sec Hub burnt orange
    when "custom"                   then ApplicationHelper::COLOR_PURPLE
    else ApplicationHelper::COLOR_GRAY
    end
  end

  # Semantic variant key for .sparc-status--<variant> (WORM, #599 Round 2).
  # Both AWS converters map to the orange variant; the type label text keeps
  # them distinguishable. AA-correct in CSS, no hex in the view.
  def converter_type_variant(converter_type)
    case converter_type
    when "cci_to_nist"                                   then "danger"
    when "cis_to_nist"                                   then "info"
    when "scap_oval_to_nist"                             then "success"
    when "aws_config_to_nist", "aws_security_hub_to_nist" then "orange"
    when "custom"                                        then "purple"
    else "neutral"
    end
  end

  def converter_relationship_color(relationship)
    case relationship
    when "equal"       then "success"
    when "equivalent"  then "primary"
    when "subset"      then "info"
    when "superset"    then "warning"
    when "intersects"  then "secondary"
    else "light"
    end
  end
end
