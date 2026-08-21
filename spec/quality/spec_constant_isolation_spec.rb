# frozen_string_literal: true

require "rails_helper"

# #1035 — a constant assigned inside a `describe`/`context` block is NOT scoped
# to that block. Ruby has no block scope for constants, so it lands on Object,
# visible to every other spec file in the run.
#
# When two spec files pick the same name, the one loaded last wins for BOTH, and
# the failure is silent in the direction that matters: an assertion that resolves
# the constant at RUN time gets the other file's value, while fixtures built at
# LOAD time still hold its own. The expectation then searches for a string that
# was never in the input and passes for free.
#
# That is not hypothetical. `SECRET` was defined by both
# spec/lib/sparc_json_formatter_spec.rb and
# spec/services/terraform_upload_inventory_service_spec.rb, and it made five
# credential-redaction checks (NIST AU-9 / IA-5(1)) vacuous — they would have
# stayed green with log redaction switched off entirely.
#
# Nothing else catches this. `rubocop-rails-omakase` does not enable
# `Lint/ConstantDefinitionInBlock`, and Ruby's own "already initialized constant"
# warning is emitted on every run but buried in suite output.
RSpec.describe "spec suite constant isolation" do
  # Parsed rather than grepped: only a constant that is genuinely top-level
  # leaks. One assigned inside `class`/`module` in a spec is namespaced and
  # harmless, and a regex cannot tell the two apart.
  def top_level_constants(path)
    tree = RubyVM::AbstractSyntaxTree.parse_file(path)
    found = []
    walk = lambda do |node|
      return unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
      # A class/module body opens a real namespace — anything inside is scoped.
      return if %i[CLASS MODULE].include?(node.type)

      found << node.children.first if node.type == :CDECL && node.children.first.is_a?(Symbol)
      node.children.each { |child| walk.call(child) }
    end
    walk.call(tree)
    found
  end

  it "defines no top-level constant in more than one spec file" do
    owners = Hash.new { |h, k| h[k] = [] }

    Dir[Rails.root.join("spec/**/*_spec.rb")].sort.each do |path|
      relative = Pathname.new(path).relative_path_from(Rails.root).to_s
      top_level_constants(path).each { |name| owners[name] << relative }
    end

    collisions = owners.select { |_name, files| files.uniq.size > 1 }

    expect(collisions).to be_empty, <<~MSG
      These constants are defined at top level by more than one spec file, so the
      file loaded last silently wins for all of them:

      #{collisions.map { |name, files| "  #{name}\n#{files.uniq.map { |f| "    - #{f}" }.join("\n")}" }.join("\n\n")}

      Scope the value to its example group instead:
        - a `let(:name)` where the value is only needed while an example runs
          (a `def` helper in the group can call it — both are instance methods);
        - a plain local variable where it is needed at LOAD time, e.g. to build
          a table of examples. Each example closes over it, so the load-time and
          run-time values cannot diverge.
    MSG
  end
end
