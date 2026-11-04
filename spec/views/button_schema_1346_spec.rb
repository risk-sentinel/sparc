# frozen_string_literal: true

require "rails_helper"

# #1346 — one button system, kept that way. v1.16.0 (#950) moved 489 buttons
# onto the sparc-action roles. The 1.18.0-rf layout pivot then moved screens
# without moving their headers onto the shared page header, and Bootstrap
# `btn btn-*` buttons survived beside sparc-action ones, taller and wrapping.
# Nothing caught it. These do.
RSpec.describe "Button schema (#1346)" do
  # Every quoted string in a view or a JavaScript file, split into class
  # tokens. A bare `btn` token is a Bootstrap button; btn-close, btn-group
  # and btn-check are other Bootstrap components and are not buttons.
  def bootstrap_buttons(glob)
    Dir[Rails.root.join(glob)].flat_map do |path|
      File.read(path).scan(/"([^"\n]*)"|'([^'\n]*)'/).filter_map do |double, single|
        text = double || single
        next unless text.split.include?("btn")

        "#{path.delete_prefix("#{Rails.root}/")}: #{text.strip[0, 90]}"
      end
    end
  end

  it "draws no Bootstrap `btn` button in a view; every button is a sparc-action role" do
    offenders = bootstrap_buttons("app/views/**/*.erb")

    expect(offenders).to be_empty, lambda {
      "#{offenders.size} Bootstrap button(s); use sparc-action roles (v1.16.0, #950):\n  " + offenders.join("\n  ")
    }
  end

  it "builds no Bootstrap `btn` button in JavaScript" do
    offenders = bootstrap_buttons("app/javascript/**/*.js")

    expect(offenders).to be_empty, lambda {
      "#{offenders.size} Bootstrap button(s) built in JavaScript:\n  " + offenders.join("\n  ")
    }
  end

  it "gives every Settings show page the shared page header" do
    pages = Dir[Rails.root.join("app/views/admin/*/show.html.erb")]
    hand_built = pages.reject { File.read(_1).match?(%r{render "shared/(page_header|document_header)"}) }
                      .map { _1.delete_prefix("#{Rails.root}/") }

    expect(pages.size).to be >= 6
    expect(hand_built).to be_empty, lambda {
      "Settings page(s) with a hand-built header; render shared/page_header:\n  " + hand_built.join("\n  ")
    }
  end
end
