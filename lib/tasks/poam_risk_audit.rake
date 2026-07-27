# #832 — find POA&M risks that predate the validation rules.
#
# `PoamRisk` used to validate only `uuid`, so rows already in the database may
# be missing OSCAL-required content (title, description, statement, status) or a
# deadline. Those rows now fail validation, which means the NEXT save of such a
# record — even an edit to an unrelated field — is rejected until the gaps are
# filled.
#
# That is deliberate: grandfathering them would preserve exactly the invalid
# data the validations exist to stop, and silently. But operators need to find
# them on their own terms rather than discovering them one failed edit at a
# time, which is what this task is for.
#
# There is deliberately NO auto-fix. Every missing field is substantive
# compliance content — a risk statement describes how the risk affects the
# system, and a deadline is a commitment to a date. Generating them would
# produce a POA&M that is schema-valid and untrue, which is the same mistake as
# an exporter synthesising required content (#816) or hdf-cli 3.3.2 inventing
# "conversion time plus one year" (#764).
namespace :sparc do
  namespace :poam do
    desc "Report POA&M risks missing OSCAL-required fields or a deadline (#832)"
    task audit_risks: :environment do
      incomplete = PoamRisk.includes(:poam_document).reject { |risk| risk.missing_required_fields.empty? }

      if incomplete.empty?
        puts "[sparc:poam:audit_risks] all #{PoamRisk.count} risks carry the required fields."
        next
      end

      puts "[sparc:poam:audit_risks] #{incomplete.size} of #{PoamRisk.count} risks are incomplete."
      puts "These cannot be saved again until the missing fields are supplied."
      puts

      incomplete.group_by(&:poam_document).each do |document, risks|
        label = document ? "#{document.name} (id=#{document.id})" : "(no document)"
        puts "  #{label}"
        risks.each do |risk|
          puts "    risk id=#{risk.id} uuid=#{risk.uuid} missing: #{risk.missing_required_fields.join(', ')}"
        end
        puts
      end

      puts "Complete them in the UI (POA&M > Risks) or via PATCH /api/v1/poam_risks/:id."
      puts "Do not batch-fill these: a statement and a deadline are commitments, not defaults."
    end
  end
end
