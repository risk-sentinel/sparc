#!/usr/bin/env ruby
# frozen_string_literal: true

# #1120 — every SPARC_* variable: where the code reads it, and where it is
# documented. Re-run it on any commit to find the two kinds of drift that
# #1120 measured by hand:
#
#   * a setting the code reads that no document mentions (11 operator
#     settings were found this way), and
#   * a setting the documents describe that nothing reads (six, one of them,
#     SPARC_OIDC_FORCE_MFA, cited for IA-2 coverage it never provided).
#
# Usage (from repo root):
#   bin/env_inventory_check.rb            # report + EXIT 1 on drift (the gate)
#   bin/env_inventory_check.rb --report   # report only, always exits 0
#   bin/env_inventory_check.rb --list     # every variable, where read, where documented
#
# spec/scripts/env_inventory_check_spec.rb runs the gate in the suite, so no
# workflow change is needed.
#
# What counts:
#   * READ — the name appears in code (app/, config/, lib/, db/, the image
#     entrypoint and its bin/lib helpers) as a string literal, a %w[] entry or
#     a shell expansion. A mention in a comment is not a read, nor is a Ruby
#     constant that happens to start SPARC_ (SPARC_ROLES). Names in
#     SparcConfig::RETIRED_VARIABLES are read only to warn, so they are not
#     reads either.
#   * DOCUMENTED — the name heads a table row in docs/ENVIRONMENT_VARIABLES.md,
#     the canonical reference. A struck-through name (~~NAME~~) is documented
#     as retired or removed, not as current.

require "set"

module EnvInventory
  extend self

  ROOT = File.expand_path("..", __dir__)

  # The tree to inspect. The spec points it at a scratch tree to prove each
  # kind of drift is caught.
  def root = ENV.fetch("ENV_INVENTORY_ROOT", ROOT)

  CODE_GLOBS = %w[
    app/**/*.{rb,erb,js,yml}
    config/**/*.{rb,yml,erb}
    lib/**/*.{rb,rake}
    db/**/*.rb
    bin/docker-entrypoint
    bin/lib/**/*.sh
    Dockerfile
  ].freeze

  REFERENCE = "docs/ENVIRONMENT_VARIABLES.md"

  # Other places an operator reads to configure SPARC. They may omit a variable
  # (the reference is complete, these are not), but they must not describe one
  # as current when nothing reads it.
  OPERATOR_DOCS = %w[wiki/Configuration.md .env.example .env.production.example].freeze

  # Read by the code and deliberately left out of the reference, with the reason.
  UNDOCUMENTED_ON_PURPOSE = {
    "SPARC_ENABLE_XLSX_UPLOADS" => "#479: deliberately left out of operator documentation"
  }.freeze

  NAME = /SPARC_[A-Z0-9_]*[A-Z0-9]/
  # A literal name: quoted, inside %w[], or a shell expansion. A prefix that
  # code completes with interpolation ("SPARC_DB_#{...}") is not a name: NAME
  # cannot end in "_", and the lookahead refuses a cut-short match.
  LITERAL = /(?:["'\[\s{]|\$\{?)(#{NAME})(?![A-Z0-9_])/

  def code_files
    CODE_GLOBS.flat_map { |glob| Dir.glob(File.join(root, glob)) }.uniq.select { |f| File.file?(f) }
  end

  def comment?(line)
    line.lstrip.start_with?("#", "<%#", "//")
  end

  # The names SparcConfig::RETIRED_VARIABLES lists, read from the source so
  # this script needs no Rails boot.
  def retired
    source = File.read(File.join(root, "app/models/sparc_config.rb"))
    block = source[/RETIRED_VARIABLES = \{(.*?)\}\.freeze/m, 1].to_s
    block.scan(/^\s*"(#{NAME})"\s*=>/).flatten.to_set
  end

  # Ruby constants named SPARC_* (SPARC_ROLES, SPARC_TYPE_MAP): code, not settings.
  def constants
    code_files.select { |f| f.end_with?(".rb") }
              .flat_map { |f| File.read(f).scan(/^[ \t]*(#{NAME})[ \t]+=[ \t]/).flatten }.to_set
  end

  # name => ["path:line", ...]
  def reads
    found = Hash.new { |h, k| h[k] = [] }
    code_files.each do |file|
      rel = file.delete_prefix("#{root}/")
      in_retired_block = false
      File.foreach(file).with_index(1) do |line, number|
        in_retired_block = true if line.include?("RETIRED_VARIABLES = {")
        if in_retired_block
          in_retired_block = false if line.include?("}.freeze")
          next
        end
        next if comment?(line)

        # A trailing Ruby/shell comment is prose too.
        code = line.sub(/\s#\s.*\z/, "")
        code.scan(LITERAL).flatten.each { |name| found[name] << "#{rel}:#{number}" }
      end
    end
    constants.each { |name| found.delete(name) }
    found
  end

  # [current, struck] name sets from the table rows of a markdown file.
  def table_names(path)
    current = Set.new
    struck = Set.new
    File.foreach(File.join(root, path)) do |line|
      cell = line[/\A\|\s*([^|]+?)\s*\|/, 1] or next
      name = cell[NAME] or next
      next unless cell.delete("`~*").strip == name

      (cell.include?("~~") ? struck : current) << name
    end
    [ current, struck ]
  end

  # Names an .env example sets or shows commented out (`# SPARC_X=...`).
  def env_example_names(path)
    File.readlines(File.join(root, path)).filter_map { |line| line[/\A#?\s*(#{NAME})=/, 1] }.to_set
  end

  def operator_doc_names(path)
    path.start_with?(".env") ? env_example_names(path) : table_names(path).first
  end

  def problems
    read = reads
    read_names = read.keys.to_set
    documented, struck = table_names(REFERENCE)
    retired_names = retired
    out = []

    (read_names - documented - UNDOCUMENTED_ON_PURPOSE.keys).sort.each do |name|
      out << "#{name} is read (#{read[name].first}) but #{REFERENCE} does not document it"
    end
    (documented - read_names).sort.each do |name|
      out << "#{REFERENCE} documents #{name} as current, but nothing reads it" \
             "#{' (it is retired: strike it through)' if retired_names.include?(name)}"
    end
    (retired_names & read_names).sort.each do |name|
      out << "#{name} is retired (SparcConfig::RETIRED_VARIABLES) but still read at #{read[name].join(', ')}"
    end
    (retired_names - struck).sort.each do |name|
      out << "#{name} is retired but #{REFERENCE} does not list it struck through (~~#{name}~~)"
    end
    OPERATOR_DOCS.each do |path|
      (operator_doc_names(path) - read_names).sort.each do |name|
        out << "#{path} shows #{name} as a setting, but nothing reads it"
      end
    end
    out
  end

  def list
    read = reads
    documented, struck = table_names(REFERENCE)
    names = (read.keys + documented.to_a + struck.to_a + retired.to_a).uniq.sort
    names.map do |name|
      where = read[name].first(3).join(", ")
      where += ", +#{read[name].size - 3} more" if read[name].size > 3
      "#{name}\n    read: #{where.empty? ? 'nowhere' : where}\n    #{documentation(name, documented, struck)}"
    end
  end

  def documentation(name, documented, struck)
    return "documented" if documented.include?(name)
    return "documented as retired" if struck.include?(name)
    return "undocumented on purpose (#{UNDOCUMENTED_ON_PURPOSE[name]})" if UNDOCUMENTED_ON_PURPOSE.key?(name)

    "UNDOCUMENTED"
  end

  def summary
    read = reads
    documented, struck = table_names(REFERENCE)
    "#{read.size} variables read in code; #{documented.size} documented as current and " \
      "#{struck.size} as retired in #{REFERENCE}; #{retired.size} in SparcConfig::RETIRED_VARIABLES"
  end

  # The command: prints the report and returns the exit status (1 on drift,
  # unless --report).
  def main(argv)
    if argv.include?("--list")
      puts list
      puts
      puts summary
      return 0
    end

    found = problems
    puts summary
    if found.empty?
      puts "No drift between the code and the documents."
      return 0
    end

    puts "#{found.size} drift finding(s):"
    found.each { |problem| puts "  - #{problem}" }
    argv.include?("--report") ? 0 : 1
  end
end

exit EnvInventory.main(ARGV) if $PROGRAM_NAME == __FILE__
