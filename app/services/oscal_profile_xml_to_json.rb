# frozen_string_literal: true

# OscalProfileXmlToJson — converts an OSCAL profile in its XML serialization to
# the OSCAL JSON model, the hash `JSON.parse` returns for NIST's own JSON
# (#1252).
#
# The XML profile import used to build a reduced copy of the profile by hand:
# it kept `with-id` and `include-all` but dropped `matching`,
# `with-child-controls`, `exclude-controls`, `removes`, the parts an alter adds
# and a set-parameter's `select`. An XML profile therefore selected and tailored
# differently from the same profile in JSON. Converting the whole model first
# and running the one JSON import path removes that second model, as #1228 did
# for catalogs.
#
# Everything a profile shares with a catalog (metadata, params, parts, props,
# links, back-matter, markup) is the catalog converter's, inherited rather than
# restated. Checked against NIST: converting NIST's XML deep-equals NIST's own
# JSON for the same document (spec/services/oscal_profile_xml_to_json_spec.rb).
#
# NIST 800-53: SI-10 (an unknown element is refused, never dropped).
class OscalProfileXmlToJson < OscalCatalogXmlToJson
  INSERT_CONTROLS = "insert-controls"

  def convert
    doc = XmlSecurity.parse(@xml, keep_blanks: true)
    doc.remove_namespaces!
    root = doc.root
    raise ConversionError, "No <profile> root element — not an OSCAL XML profile." unless root&.name == "profile"

    { "profile" => profile(root) }
  rescue Nokogiri::XML::SyntaxError => e
    raise ConversionError, "Not well-formed XML: #{e.message}"
  end

  private

  def profile(node)
    obj = attrs(node, "uuid")
    each_child(node) do |child, out|
      case child.name
      when "metadata"    then obj["metadata"] = metadata(child)
      when "import"      then push(obj, "imports", import(child))
      when "merge"       then obj["merge"] = merge(child)
      when "modify"      then obj["modify"] = modify(child)
      when "back-matter" then obj["back-matter"] = back_matter(child)
      else out.unknown!
      end
    end
    obj
  end

  # ── Selection ──────────────────────────────────────────────────────────

  def import(node)
    selection(node, attrs(node, "href"))
  end

  # include-all / include-controls / exclude-controls, shared by <import> and
  # a custom merge's <insert-controls>.
  def selection(node, obj)
    each_child(node) do |child, out|
      case child.name
      when "include-all"      then obj["include-all"] = {}
      when "include-controls" then push(obj, "include-controls", select_controls(child))
      when "exclude-controls" then push(obj, "exclude-controls", select_controls(child))
      else out.unknown!
      end
    end
    obj
  end

  def select_controls(node)
    obj = attrs(node, "with-child-controls")
    each_child(node) do |child, out|
      case child.name
      when "with-id"  then push(obj, "with-ids", plain(child))
      when "matching" then push(obj, "matching", attrs(child, "pattern"))
      else out.unknown!
      end
    end
    obj
  end

  # ── Merge ──────────────────────────────────────────────────────────────

  def merge(node)
    obj = {}
    each_child(node) do |child, out|
      case child.name
      when "combine" then obj["combine"] = attrs(child, "method")
      when "flat"    then obj["flat"] = {}
      when "as-is"   then obj["as-is"] = plain(child) == "true"
      when "custom"  then obj["custom"] = custom(child)
      else out.unknown!
      end
    end
    obj
  end

  def custom(node)
    obj = {}
    each_child(node) do |child, out|
      case child.name
      when "group"           then push(obj, "groups", custom_group(child))
      when INSERT_CONTROLS then push(obj, INSERT_CONTROLS, insert_controls(child))
      else out.unknown!
      end
    end
    obj
  end

  def custom_group(node)
    obj = attrs(node, "id", "class")
    each_child(node) do |child, out|
      case child.name
      when "title"           then obj["title"] = markup_line(child)
      when "param"           then push(obj, "params", param(child))
      when "prop"            then push(obj, "props", prop(child))
      when "link"            then push(obj, "links", link(child))
      when "part"            then push(obj, "parts", part(child))
      when "group"           then push(obj, "groups", custom_group(child))
      when INSERT_CONTROLS then push(obj, INSERT_CONTROLS, insert_controls(child))
      else out.unknown!
      end
    end
    obj
  end

  def insert_controls(node)
    selection(node, attrs(node, "order"))
  end

  # ── Modify ─────────────────────────────────────────────────────────────

  def modify(node)
    obj = {}
    each_child(node) do |child, out|
      case child.name
      when "set-parameter" then push(obj, "set-parameters", set_parameter(child))
      when "alter"         then push(obj, "alters", alter(child))
      else out.unknown!
      end
    end
    obj
  end

  # A set-parameter carries a param's fields under `param-id` rather than `id`.
  def set_parameter(node)
    obj = attrs(node, "param-id", "class", "depends-on")
    each_child(node) do |child, out|
      case child.name
      when "prop"       then push(obj, "props", prop(child))
      when "link"       then push(obj, "links", link(child))
      when "label"      then obj["label"] = markup_line(child)
      when "usage"      then obj["usage"] = markup_multiline(child)
      when "constraint" then push(obj, "constraints", constraint(child))
      when "guideline"  then push(obj, "guidelines", { "prose" => markup_multiline(child) })
      when "value"      then push(obj, "values", plain(child))
      when "select"     then obj["select"] = select(child)
      else out.unknown!
      end
    end
    obj
  end

  def alter(node)
    obj = attrs(node, "control-id")
    each_child(node) do |child, out|
      case child.name
      when "remove" then push(obj, "removes", attrs(child, "by-name", "by-class", "by-id", "by-item-name", "by-ns"))
      when "add"    then push(obj, "adds", add(child))
      else out.unknown!
      end
    end
    obj
  end

  def add(node)
    obj = attrs(node, "position", "by-id")
    each_child(node) do |child, out|
      case child.name
      when "title" then obj["title"] = markup_line(child)
      when "param" then push(obj, "params", param(child))
      when "prop"  then push(obj, "props", prop(child))
      when "link"  then push(obj, "links", link(child))
      when "part"  then push(obj, "parts", part(child))
      else out.unknown!
      end
    end
    obj
  end
end
