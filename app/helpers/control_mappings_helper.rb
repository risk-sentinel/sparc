# frozen_string_literal: true

module ControlMappingsHelper
  def mapping_status_color(status)
    case status
    when "complete"     then "success"
    when "draft"        then "warning"
    when "not-complete" then "info"
    when "deprecated"   then "secondary"
    when "superseded"   then "secondary"
    else "light"
    end
  end

  def mapping_relationship_color(relationship)
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
