#!/usr/bin/env ruby
# frozen_string_literal: true

# Sonar threshold (#1362): no new Sonar issues reach the target branch.
#
# Compares two raw `hdf fetch sonarqube --format raw` files:
#
#   --base  the PR's target branch, every issue in every status (the baseline)
#   --head  the pull request's own analysis
#
# A head issue is NEW when it is open and matches no base issue in any status.
# Matching uses Sonar's issue key first, then rule + file + Sonar's line hash
# (or the message when there is no hash), so an issue that moved lines is not
# counted as new. A head issue that matches a base issue resolved as False
# positive or Accepted keeps that resolution.
#
# Why the raw files and not the HDF: hdf groups issues into one requirement per
# rule and keeps Sonar's key and hash only for the first issue in each group
# (`sonarqube/key`, `sonarqube/hash` tags). The raw file keeps them per issue.
#
# Resolved issues (False positive, Accepted, Fixed) are counted and reported,
# never gated: Sonar's False positive resolution is how the team documents and
# tracks those decisions, so the summary keeps their numbers visible as a trend.
#
# hdf's raw file keeps only Sonar's legacy `status` (OPEN, CONFIRMED, REOPENED,
# RESOLVED, CLOSED): it drops `issueStatus` and `resolution`, so it cannot tell
# a False positive from an Accepted issue. Open-vs-resolved, which is all the
# gate needs, is exact either way. For the trend counts, pass --base-counts: the
# `issueStatuses` facet of SonarCloud's /api/issues/search for the target
# branch, which sonar_fetch saves next to the raw file.
#
# FAILS CLOSED. A missing, unreadable or truncated input is an error in every
# mode: an empty fetch would otherwise read as "no new issues".
#
# Threshold file (docs/compliance/sonar-threshold.yml):
#
#   mode: report      # report: summarise and pass. enforce: fail on a breach
#   new_issues:
#     max: 0
#
# Exit status: 0 pass (or a breach in report mode), 1 breach in enforce mode,
# 2 bad input or bad threshold file.
#
# NIST SP 800-53 Rev 5: SA-11 (developer testing: static analysis findings are
# gated before merge), RA-5 (vulnerability monitoring), CA-7 (continuous
# monitoring: the summary carries resolution counts run over run).

require "json"
require "optparse"
require "yaml"

OPEN_ISSUE_STATUSES = %w[OPEN CONFIRMED].freeze
OPEN_LEGACY_STATUSES = %w[OPEN CONFIRMED REOPENED].freeze
MODES = %w[report enforce].freeze
SHOWN_NEW_ISSUES = 50

def fail_input(message)
  warn "::error::sonar_new_issues: #{message}"
  exit 2
end

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: sonar_new_issues.rb --base RAW --head RAW --threshold YML [--summary FILE]"
  opts.on("--base FILE", "raw fetch of the target branch (all issues)") { |v| options[:base] = v }
  opts.on("--head FILE", "raw fetch of the pull request") { |v| options[:head] = v }
  opts.on("--threshold FILE", "threshold file") { |v| options[:threshold] = v }
  opts.on("--base-counts FILE", "issueStatuses facet for the target branch (trend counts)") { |v| options[:base_counts] = v }
  opts.on("--summary FILE", "append a Markdown summary here (GITHUB_STEP_SUMMARY)") { |v| options[:summary] = v }
end.parse!

%i[base head threshold].each { |k| fail_input("--#{k} is required") unless options[k] }

def load_raw(path, label)
  fail_input("#{label} file #{path} does not exist") unless File.file?(path)
  doc = begin
    JSON.parse(File.read(path))
  rescue JSON::ParserError => e
    fail_input("#{label} file #{path} is not JSON (#{e.message.lines.first&.strip})")
  end
  fail_input("#{label} file #{path} is not a raw Sonar issues document") unless doc.is_a?(Hash)
  issues = doc["issues"]
  fail_input("#{label} file #{path} has no issues[] array") unless issues.is_a?(Array)
  total = doc["total"]
  unless total.is_a?(Integer) && total == issues.length
    fail_input("#{label} file #{path} reports total=#{total.inspect} but holds #{issues.length} issues; " \
               "refusing to judge a truncated fetch")
  end
  issues
end

def load_threshold(path)
  fail_input("threshold file #{path} does not exist") unless File.file?(path)
  doc = YAML.safe_load(File.read(path))
  fail_input("threshold file #{path} is not a mapping") unless doc.is_a?(Hash)
  unknown = doc.keys - %w[mode new_issues]
  fail_input("threshold file #{path} has unknown key(s): #{unknown.join(', ')}") unless unknown.empty?
  mode = doc["mode"]
  fail_input("threshold mode must be one of #{MODES.join(', ')} (got #{mode.inspect})") unless MODES.include?(mode)
  max = doc.dig("new_issues", "max")
  fail_input("threshold new_issues.max must be a non-negative integer (got #{max.inspect})") unless max.is_a?(Integer) && max >= 0
  [ mode, max ]
end

def open_issue?(issue)
  if issue["issueStatus"]
    OPEN_ISSUE_STATUSES.include?(issue["issueStatus"])
  else
    OPEN_LEGACY_STATUSES.include?(issue["status"])
  end
end

# Bucket for the trend counts. issueStatus and resolution are present in
# Sonar's own API responses; hdf's raw file carries neither, only `status`.
def category(issue)
  return "open" if open_issue?(issue)

  case issue["issueStatus"] || issue["resolution"]
  when "FALSE_POSITIVE", "FALSE-POSITIVE" then "false_positive"
  when "ACCEPTED", "WONTFIX" then "accepted"
  when "FIXED", "REMOVED" then "fixed"
  else issue["status"] == "CLOSED" ? "fixed" : "resolved"
  end
end

# The issueStatuses facet: {"facets":[{"property":"issueStatuses","values":[{"val":"OPEN","count":402},...]}]}
def load_counts(path)
  fail_input("base counts file #{path} does not exist") unless File.file?(path)
  doc = begin
    JSON.parse(File.read(path))
  rescue JSON::ParserError
    fail_input("base counts file #{path} is not JSON")
  end
  facet = Array(doc.is_a?(Hash) ? doc["facets"] : nil).find { |f| f["property"] == "issueStatuses" }
  fail_input("base counts file #{path} has no issueStatuses facet") unless facet
  by_status = facet["values"].to_h { |v| [ v["val"], v["count"].to_i ] }
  {
    "open" => by_status.fetch("OPEN", 0) + by_status.fetch("CONFIRMED", 0),
    "false_positive" => by_status.fetch("FALSE_POSITIVE", 0),
    "accepted" => by_status.fetch("ACCEPTED", 0),
    "fixed" => by_status.fetch("FIXED", 0)
  }
end

# The component key is "<project>:<path>" (a branch or PR suffix is not part
# of it), so the path after the first colon is stable across branches.
def file_of(issue)
  issue["component"].to_s.split(":", 2).last.to_s
end

def fingerprint(issue)
  [ issue["rule"], file_of(issue), issue["hash"].to_s.empty? ? issue["message"].to_s : issue["hash"] ]
end

def severity_of(issue)
  impacts = Array(issue["impacts"]).map { |i| "#{i['softwareQuality']}:#{i['severity']}" }
  impacts.empty? ? issue["severity"].to_s : impacts.join(", ")
end

def md_cell(text)
  text.to_s.gsub("|", "\\|").gsub(/\s+/, " ")
end

mode, max_new = load_threshold(options[:threshold])
base = load_raw(options[:base], "base")
head = load_raw(options[:head], "head")

base_by_key = base.to_h { |i| [ i["key"], i ] }
base_by_fingerprint = base.each_with_object({}) { |i, h| h[fingerprint(i)] ||= i }

new_issues = []
inherited = Hash.new(0)
head.select { |i| open_issue?(i) }.each do |issue|
  match = base_by_key[issue["key"]] || base_by_fingerprint[fingerprint(issue)]
  if match.nil?
    new_issues << issue
  else
    inherited[category(match)] += 1
  end
end

base_counts = options[:base_counts] ? load_counts(options[:base_counts]) : base.map { |i| category(i) }.tally
head_open = head.count { |i| open_issue?(i) }
breach = new_issues.length > max_new
verdict =
  if !breach then "PASS"
  elsif mode == "enforce" then "FAIL"
  else "BREACH (report mode, not blocking)"
  end

lines = []
lines << "## Sonar: new issues on this branch"
lines << ""
lines << "| | Count |"
lines << "|---|---|"
lines << "| New open issues (threshold max #{max_new}) | **#{new_issues.length}** |"
lines << "| Open issues in the PR analysis | #{head_open} |"
lines << "| Open in the PR, already on the target branch | #{inherited.values.sum} |"
lines << "| Target branch: open | #{base_counts.fetch('open', 0)} |"
lines << "| Target branch: false positive | #{base_counts.fetch('false_positive', 0)} |"
lines << "| Target branch: accepted | #{base_counts.fetch('accepted', 0)} |"
lines << "| Target branch: fixed | #{base_counts.fetch('fixed', 0)} |"
lines << "| Target branch: resolved, FP or accepted (no counts file) | #{base_counts['resolved']} |" if base_counts.key?("resolved")
lines << ""
lines << "Mode: `#{mode}`. Result: **#{verdict}**."
unless new_issues.empty?
  lines << ""
  lines << "| Rule | File | Line | Severity | Message |"
  lines << "|---|---|---|---|---|"
  new_issues.first(SHOWN_NEW_ISSUES).each do |i|
    lines << "| `#{md_cell(i['rule'])}` | `#{md_cell(file_of(i))}` | #{i['line']} | #{md_cell(severity_of(i))} | #{md_cell(i['message'])} |"
  end
  lines << "" << "#{new_issues.length - SHOWN_NEW_ISSUES} more not shown." if new_issues.length > SHOWN_NEW_ISSUES
  lines << ""
  lines << "Fix each issue, or resolve it in SonarCloud as False positive or Accepted with a comment."
end
report = lines.join("\n") + "\n"

puts report
File.open(options[:summary], "a") { |f| f.write(report) } if options[:summary]

puts "Sonar new-issue threshold: #{verdict} (#{new_issues.length} new, max #{max_new}, mode #{mode})"
if breach
  warn "::#{mode == 'enforce' ? 'error' : 'warning'}::#{new_issues.length} new Sonar issue(s) on this branch (max #{max_new})"
  exit 1 if mode == "enforce"
end
exit 0
