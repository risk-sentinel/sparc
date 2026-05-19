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
    when "cci_to_nist"              then "#e74c3c"
    when "cis_to_nist"              then "#3498db"
    when "scap_oval_to_nist"        then "#2ecc71"
    when "aws_config_to_nist"       then "#ff9900"  # AWS orange
    when "aws_security_hub_to_nist" then "#ec7211"  # AWS Sec Hub burnt orange
    when "custom"                   then "#9b59b6"
    else "#95a5a6"
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
