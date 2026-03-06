namespace :sar do
  desc "Backfill control_family and cached_result on existing sar_controls"
  task backfill: :environment do
    total = SarControl.count
    updated = 0

    SarControl.includes(:sar_control_fields).find_each(batch_size: 1000) do |control|
      family = control.control_id.to_s.split("-").first.upcase.presence
      result_field = control.sar_control_fields.find { |f| f.field_name == "result" }

      control.update_columns(
        control_family: family,
        cached_result:  result_field&.field_value
      )

      updated += 1
      print "\rBackfilled #{updated}/#{total} controls..." if (updated % 1000).zero?
    end

    puts "\nDone. Backfilled #{updated} controls."
  end
end
