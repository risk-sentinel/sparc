# frozen_string_literal: true

# OscalCatalogXmlToJson — converts an OSCAL catalog in its XML serialization to
# the OSCAL JSON model, the same hash `JSON.parse` returns for NIST's own JSON
# (#1228).
#
# Why SPARC converts at all:
#
# 1. NIST's fixes to SP 800-53 Rev 5 (SA-15(13), SA-24, SI-02(07)) were made in
#    the oscal-content XML SOURCE, before any JSON carried them. SPARC vendors
#    that XML and generates the JSON; at the pinned commit the result is
#    identical to NIST's own published JSON (recorded in the provenance).
# 2. The XML catalog import used to read the XML with its own, smaller model.
#    It dropped `<value>`, flattened guideline prose to plain text and never
#    stored parts, so an XML catalog imported differently from the same catalog
#    in JSON. Converting first and running the one JSON import path removes the
#    second model altogether (the move the YAML import already makes).
#
# The output is checked against NIST: converting the v5.2.0 XML fixture
# deep-equals NIST's own v5.2.0 JSON (spec/services/oscal_catalog_xml_to_json_spec.rb).
#
# Markup follows NIST's converter:
#
#   markup-line       (title, label, choice, citation text, …) → one string
#   markup-multiline  (part prose, guideline prose, remarks, …) → blocks joined "\n\n"
#
#   <insert type="param" id-ref="x"/> → {{ insert: param, x }}
#   <a href="u">t</a>                 → [t](u)
#   <em>/<i>                          → *x*
#   <strong>/<b>                      → **x**
#   <q>                               → "x"
#   <code>                            → `x`
#   <sub> / <sup>                     → ~x~ / ^x^
#
# The parser is XmlSecurity's (no network, no entity substitution). Blank text
# nodes are KEPT here: in mixed content the space between `</em>` and `<a>` is a
# word boundary, and the shared parser's `noblanks` would delete it.
#
# NIST 800-53: SI-10 (information input validation — an unknown element is
# refused, never dropped). See: docs/compliance/nist-sp800-53-rev5-mapping.md
class OscalCatalogXmlToJson
  # Recorded in the vendored catalog's provenance sidecar. Bump it whenever a
  # change here could change the generated JSON, so the drift spec and the
  # provenance agree about what produced the committed file.
  VERSION = "1.0.0"

  OSCAL_NS = "http://csrc.nist.gov/ns/oscal/1.0"

  class ConversionError < StandardError; end

  BLOCK_ELEMENTS = %w[p h1 h2 h3 h4 h5 h6 ul ol pre table blockquote hr].freeze

  def self.convert(xml)
    new(xml).convert
  end

  def initialize(xml)
    @xml = xml.is_a?(String) ? xml : xml.to_s
  end

  def convert
    doc = XmlSecurity.parse(@xml, keep_blanks: true)
    doc.remove_namespaces!
    root = doc.root
    raise ConversionError, "No <catalog> root element — not an OSCAL XML catalog." unless root&.name == "catalog"

    { "catalog" => catalog(root) }
  rescue Nokogiri::XML::SyntaxError => e
    raise ConversionError, "Not well-formed XML: #{e.message}"
  end

  private

  # ── Models ─────────────────────────────────────────────────────────────

  def catalog(node)
    obj = attrs(node, "uuid")
    each_child(node) do |child, out|
      case child.name
      when "metadata"    then obj["metadata"] = metadata(child)
      when "param"       then push(obj, "params", param(child))
      when "control"     then push(obj, "controls", control(child))
      when "group"       then push(obj, "groups", group(child))
      when "back-matter" then obj["back-matter"] = back_matter(child)
      else out.unknown!
      end
    end
    obj
  end

  def group(node)
    obj = attrs(node, "id", "class")
    each_child(node) do |child, out|
      case child.name
      when "title"   then obj["title"] = markup_line(child)
      when "param"   then push(obj, "params", param(child))
      when "prop"    then push(obj, "props", prop(child))
      when "link"    then push(obj, "links", link(child))
      when "part"    then push(obj, "parts", part(child))
      when "group"   then push(obj, "groups", group(child))
      when "control" then push(obj, "controls", control(child))
      else out.unknown!
      end
    end
    obj
  end

  def control(node)
    obj = attrs(node, "id", "class")
    each_child(node) do |child, out|
      case child.name
      when "title"   then obj["title"] = markup_line(child)
      when "param"   then push(obj, "params", param(child))
      when "prop"    then push(obj, "props", prop(child))
      when "link"    then push(obj, "links", link(child))
      when "part"    then push(obj, "parts", part(child))
      when "control" then push(obj, "controls", control(child))
      else out.unknown!
      end
    end
    obj
  end

  def param(node)
    obj = attrs(node, "id", "class", "depends-on")
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
      when "remarks"    then obj["remarks"] = markup_multiline(child)
      else out.unknown!
      end
    end
    obj
  end

  def constraint(node)
    obj = {}
    each_child(node) do |child, out|
      case child.name
      when "description" then obj["description"] = markup_multiline(child)
      when "test"        then push(obj, "tests", test(child))
      else out.unknown!
      end
    end
    obj
  end

  def test(node)
    obj = {}
    each_child(node) do |child, out|
      case child.name
      when "expression" then obj["expression"] = plain(child)
      when "remarks"    then obj["remarks"] = markup_multiline(child)
      else out.unknown!
      end
    end
    obj
  end

  def select(node)
    obj = attrs(node, "how-many")
    each_child(node) do |child, out|
      case child.name
      when "choice" then push(obj, "choice", markup_line(child))
      else out.unknown!
      end
    end
    obj
  end

  # A part's markup blocks (p, ul, …) sit between its props and its child
  # parts; they become `prose`, one markup-multiline string.
  def part(node)
    obj = attrs(node, "id", "name", "ns", "class")
    blocks = []
    each_child(node) do |child, out|
      case child.name
      when "title" then obj["title"] = markup_line(child)
      when "prop"  then push(obj, "props", prop(child))
      when "part"  then push(obj, "parts", part(child))
      when "link"  then push(obj, "links", link(child))
      else
        BLOCK_ELEMENTS.include?(child.name) ? blocks << child : out.unknown!
      end
    end
    prose = render_blocks(blocks)
    obj["prose"] = prose unless blocks.empty?
    obj
  end

  def prop(node)
    obj = attrs(node, "name", "uuid", "ns", "value", "class", "group")
    each_child(node) do |child, out|
      child.name == "remarks" ? obj["remarks"] = markup_multiline(child) : out.unknown!
    end
    obj
  end

  def link(node)
    obj = attrs(node, "href", "rel", "media-type", "resource-fragment")
    each_child(node) do |child, out|
      child.name == "text" ? obj["text"] = markup_line(child) : out.unknown!
    end
    obj
  end

  def metadata(node)
    obj = {}
    each_child(node) do |child, out|
      case child.name
      when "title"              then obj["title"] = markup_line(child)
      when "published", "last-modified", "version", "oscal-version"
        obj[child.name] = plain(child)
      when "revisions"          then obj["revisions"] = elements(child).map { |r| revision(r) }
      when "document-id"        then push(obj, "document-ids", document_id(child))
      when "prop"               then push(obj, "props", prop(child))
      when "link"               then push(obj, "links", link(child))
      when "role"               then push(obj, "roles", role(child))
      when "location"           then push(obj, "locations", location(child))
      when "party"              then push(obj, "parties", party(child))
      when "responsible-party"  then push(obj, "responsible-parties", responsible_party(child))
      when "action"             then push(obj, "actions", action(child))
      when "remarks"            then obj["remarks"] = markup_multiline(child)
      else out.unknown!
      end
    end
    obj
  end

  def revision(node)
    obj = {}
    each_child(node) do |child, out|
      case child.name
      when "title" then obj["title"] = markup_line(child)
      when "published", "last-modified", "version", "oscal-version"
        obj[child.name] = plain(child)
      when "prop"    then push(obj, "props", prop(child))
      when "link"    then push(obj, "links", link(child))
      when "remarks" then obj["remarks"] = markup_multiline(child)
      else out.unknown!
      end
    end
    obj
  end

  def document_id(node)
    attrs(node, "scheme").merge("identifier" => plain(node))
  end

  def role(node)
    obj = attrs(node, "id")
    each_child(node) do |child, out|
      case child.name
      when "title"       then obj["title"] = markup_line(child)
      when "short-name"  then obj["short-name"] = plain(child)
      when "description" then obj["description"] = markup_multiline(child)
      when "prop"        then push(obj, "props", prop(child))
      when "link"        then push(obj, "links", link(child))
      when "remarks"     then obj["remarks"] = markup_multiline(child)
      else out.unknown!
      end
    end
    obj
  end

  def location(node)
    obj = attrs(node, "uuid")
    each_child(node) do |child, out|
      case child.name
      when "title"            then obj["title"] = markup_line(child)
      when "address"          then obj["address"] = address(child)
      when "email-address"    then push(obj, "email-addresses", plain(child))
      when "telephone-number" then push(obj, "telephone-numbers", telephone(child))
      when "url"              then push(obj, "urls", plain(child))
      when "prop"             then push(obj, "props", prop(child))
      when "link"             then push(obj, "links", link(child))
      when "remarks"          then obj["remarks"] = markup_multiline(child)
      else out.unknown!
      end
    end
    obj
  end

  def party(node)
    obj = attrs(node, "uuid", "type")
    each_child(node) do |child, out|
      case child.name
      when "name", "short-name" then obj[child.name] = plain(child)
      when "external-id"        then push(obj, "external-ids", attrs(child, "scheme").merge("id" => plain(child)))
      when "prop"               then push(obj, "props", prop(child))
      when "link"               then push(obj, "links", link(child))
      when "email-address"      then push(obj, "email-addresses", plain(child))
      when "telephone-number"   then push(obj, "telephone-numbers", telephone(child))
      when "address"            then push(obj, "addresses", address(child))
      when "location-uuid"      then push(obj, "location-uuids", plain(child))
      when "member-of-organization" then push(obj, "member-of-organizations", plain(child))
      when "remarks"            then obj["remarks"] = markup_multiline(child)
      else out.unknown!
      end
    end
    obj
  end

  def address(node)
    obj = attrs(node, "type")
    each_child(node) do |child, out|
      case child.name
      when "addr-line" then push(obj, "addr-lines", plain(child))
      when "city", "state", "postal-code", "country" then obj[child.name] = plain(child)
      else out.unknown!
      end
    end
    obj
  end

  def telephone(node)
    attrs(node, "type").merge("number" => plain(node))
  end

  def responsible_party(node)
    obj = attrs(node, "role-id")
    each_child(node) do |child, out|
      case child.name
      when "party-uuid" then push(obj, "party-uuids", plain(child))
      when "prop"       then push(obj, "props", prop(child))
      when "link"       then push(obj, "links", link(child))
      when "remarks"    then obj["remarks"] = markup_multiline(child)
      else out.unknown!
      end
    end
    obj
  end

  def action(node)
    obj = attrs(node, "uuid", "date", "type", "system")
    each_child(node) do |child, out|
      case child.name
      when "prop"              then push(obj, "props", prop(child))
      when "link"              then push(obj, "links", link(child))
      when "responsible-party" then push(obj, "responsible-parties", responsible_party(child))
      when "remarks"           then obj["remarks"] = markup_multiline(child)
      else out.unknown!
      end
    end
    obj
  end

  def back_matter(node)
    obj = {}
    each_child(node) do |child, out|
      child.name == "resource" ? push(obj, "resources", resource(child)) : out.unknown!
    end
    obj
  end

  def resource(node)
    obj = attrs(node, "uuid")
    each_child(node) do |child, out|
      case child.name
      when "title"       then obj["title"] = markup_line(child)
      when "description" then obj["description"] = markup_multiline(child)
      when "prop"        then push(obj, "props", prop(child))
      when "document-id" then push(obj, "document-ids", document_id(child))
      when "citation"    then obj["citation"] = citation(child)
      when "rlink"       then push(obj, "rlinks", rlink(child))
      when "base64"      then obj["base64"] = attrs(child, "filename", "media-type").merge("value" => plain(child))
      when "remarks"     then obj["remarks"] = markup_multiline(child)
      else out.unknown!
      end
    end
    obj
  end

  def citation(node)
    obj = {}
    each_child(node) do |child, out|
      case child.name
      when "text" then obj["text"] = markup_line(child)
      when "prop" then push(obj, "props", prop(child))
      when "link" then push(obj, "links", link(child))
      else out.unknown!
      end
    end
    obj
  end

  def rlink(node)
    obj = attrs(node, "href", "media-type")
    each_child(node) do |child, out|
      child.name == "hash" ? push(obj, "hashes", attrs(child, "algorithm").merge("value" => plain(child))) : out.unknown!
    end
    obj
  end

  # ── Structure helpers ──────────────────────────────────────────────────

  # Collects an unknown child so the caller can refuse it. A converter that
  # quietly skipped an element it did not recognise would hand the importer a
  # catalog with something missing and no way to tell.
  class Unknown
    def initialize(parent, child)
      @parent = parent
      @child = child
    end

    def unknown!
      raise ConversionError, "Unexpected <#{@child.name}> inside <#{@parent.name}>"
    end
  end

  def each_child(node)
    elements(node).each { |child| yield child, Unknown.new(node, child) }
  end

  def elements(node)
    node.children.select(&:element?)
  end

  def attrs(node, *names)
    names.each_with_object({}) do |name, obj|
      value = node[name]
      obj[name] = value unless value.nil?
    end
  end

  def push(obj, key, value)
    (obj[key] ||= []) << value
  end

  # A plain (non-markup) field: its text, whitespace trimmed.
  def plain(node)
    node.text.strip
  end

  # ── Markup ─────────────────────────────────────────────────────────────

  def markup_line(node)
    inline(node.children)
  end

  def markup_multiline(node)
    blocks = elements(node)
    if blocks.empty?
      # Bare text with no block wrapper — tolerated rather than lost.
      return inline(node.children).strip
    end

    render_blocks(blocks)
  end

  def render_blocks(blocks)
    blocks.map { |block| render_block(block) }.join("\n\n")
  end

  def render_block(node)
    case node.name
    when "p"                     then inline(node.children)
    when /\Ah([1-6])\z/          then "#{'#' * Regexp.last_match(1).to_i} #{inline(node.children).strip}"
    when "ul", "ol"              then render_list(node, 0)
    when "pre"                   then "```\n#{node.text}\n```"
    when "blockquote"            then render_blocks(elements(node)).lines.map { |l| "> #{l}" }.join
    when "hr"                    then "---"
    when "table"                 then render_table(node)
    else
      raise ConversionError, "Unexpected block <#{node.name}>"
    end
  end

  def render_list(node, depth)
    marker = node.name == "ol" ? "1." : "-"
    elements(node).flat_map do |li|
      raise ConversionError, "Unexpected <#{li.name}> inside <#{node.name}>" unless li.name == "li"

      text_nodes = li.children.reject { |c| c.element? && %w[ul ol].include?(c.name) }
      lines = [ "#{'  ' * depth}#{marker} #{inline(text_nodes).strip}" ]
      li.children.select { |c| c.element? && %w[ul ol].include?(c.name) }
        .each { |sub| lines << render_list(sub, depth + 1) }
      lines
    end.join("\n")
  end

  def render_table(node)
    rows = node.xpath(".//tr").map do |tr|
      tr.children.select(&:element?).map { |cell| inline(cell.children).strip }
    end
    return "" if rows.empty?

    header, *body = rows
    out = [ "| #{header.join(' | ')} |", "|#{header.map { ' --- |' }.join}" ]
    body.each { |cells| out << "| #{cells.join(' | ')} |" }
    out.join("\n")
  end

  def inline(nodes)
    nodes.map { |child| inline_node(child) }.join
  end

  def inline_node(node)
    return escape(node.text.gsub(/\s+/, " ")) if node.text?
    return "" unless node.element?

    case node.name
    when "insert"       then "{{ insert: #{node['type']}, #{node['id-ref']} }}"
    when "a"            then "[#{inline(node.children)}](#{node['href']})"
    when "em", "i"      then "*#{inline(node.children)}*"
    when "strong", "b"  then "**#{inline(node.children)}**"
    when "q"            then "\"#{inline(node.children)}\""
    when "code"         then "`#{node.text}`"
    when "sub"          then "~#{inline(node.children)}~"
    when "sup"          then "^#{inline(node.children)}^"
    when "img"          then "![#{node['alt']}](#{node['src']})"
    when "br"           then "\n"
    else
      raise ConversionError, "Unexpected inline <#{node.name}>"
    end
  end

  # NIST's converter escapes the characters markdown would otherwise read as
  # markup. Measured on NIST's own output: a literal `"` arrives as `\"`, which
  # is how `<q>` (rendered as a bare `"`) stays distinguishable from text.
  def escape(text)
    text.gsub(/([`~^*"])/) { "\\#{Regexp.last_match(1)}" }
  end
end
