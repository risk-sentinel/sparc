# frozen_string_literal: true

class ConvertersController < ApplicationController
  before_action :authorize_converter_write!, only: [
    :new, :create, :edit, :update, :destroy, :import, :do_import
  ]
  before_action :set_converter, only: [
    :show, :edit, :update, :destroy, :export
  ]

  def index
    @converters    = Converter.sorted
    @total_count   = @converters.size
    @complete_count = @converters.count { |c| c.status == "complete" }
    @draft_count   = @converters.count { |c| c.status == "draft" }

    # Aggregate coverage stats across all converters
    all_entries = ConverterEntry.joins(:converter).pluck(:target_id)
    @unique_targets = all_entries.uniq.size
    @family_count   = all_entries.map { |t| t.gsub(/-\d+.*/, "").upcase }.uniq.size
  end

  def show
    @entries = @converter.converter_entries.includes(:converter)
    @entry   = ConverterEntry.new
    @stats   = @converter.coverage_stats
  end

  def new
    @converter = Converter.new
  end

  def create
    @converter = Converter.new(converter_params)

    if @converter.save
      audit_log("converter_created", subject: @converter, metadata: { name: @converter.name })
      redirect_to @converter, flash: { success: "Converter created." }
    else
      flash.now[:error] = "Failed to create converter."
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @converter.update(converter_params)
      audit_log("converter_updated", subject: @converter, metadata: { name: @converter.name })
      redirect_to @converter, flash: { success: "Converter updated." }
    else
      flash.now[:error] = "Failed to update converter."
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @converter.name
    audit_log("converter_deleted", subject: @converter, metadata: { name: name })
    @converter.destroy
    redirect_to converters_path, flash: { success: "Converter '#{name}' deleted." }
  end

  # GET /converters/import
  def import
    # Render import form
  end

  # POST /converters/do_import
  def do_import
    file = params[:file]
    unless file
      redirect_to import_converters_path, flash: { error: "Please select a JSON file to import." }
      return
    end

    begin
      data = JSON.parse(file.read)
      converter = build_converter_from_json(data, file.original_filename)

      if converter.save
        count = import_entries_from_json(converter, data)
        audit_log("converter_imported", subject: converter, metadata: { name: converter.name, entries: count })
        redirect_to converter, flash: { success: "Imported converter '#{converter.name}' with #{count} entries." }
      else
        redirect_to import_converters_path, flash: { error: "Failed to import: #{converter.errors.full_messages.join(', ')}" }
      end
    rescue JSON::ParserError => e
      redirect_to import_converters_path, flash: { error: "Invalid JSON: #{e.message}" }
    end
  end

  # GET /converters/:id/export
  def export
    json_data = build_export_json(@converter)
    audit_log("converter_exported", subject: @converter, metadata: { name: @converter.name, format: "json" })
    send_data JSON.pretty_generate(json_data),
              filename: "#{@converter.name.parameterize}_converter_#{Date.today}.json",
              type: "application/json",
              disposition: "attachment"
  end

  private

  def set_converter
    @converter = Converter.find(params[:id])
  end

  def converter_params
    params.require(:converter).permit(
      :name, :description, :converter_type, :version,
      :status, :source_framework, :target_framework
    )
  end

  def authorize_converter_write!
    authorize_permission!("converters.write")
  end

  # Build a Converter record from imported JSON
  def build_converter_from_json(data, filename)
    converter_type = detect_converter_type(data)
    Converter.new(
      name: data["description"]&.truncate(100) || filename.gsub(/\.json$/i, ""),
      description: data["description"],
      converter_type: converter_type,
      version: data["version"] || "1.0",
      status: "draft",
      source_framework: data["source"],
      target_framework: "NIST SP 800-53"
    )
  end

  # Detect converter type from JSON format field
  def detect_converter_type(data)
    case data["format"]
    when "cci_mapping" then "cci_to_nist"
    when "cis_mapping" then "cis_to_nist"
    when "scap_mapping" then "scap_oval_to_nist"
    else "custom"
    end
  end

  # Import entries from JSON data into a converter
  def import_entries_from_json(converter, data)
    count = 0
    case data["format"]
    when "cci_mapping"
      count = import_cci_entries(converter, data)
    when "cis_mapping"
      count = import_cis_entries(converter, data)
    when "scap_mapping"
      count = import_scap_entries(converter, data)
    else
      count = import_generic_entries(converter, data)
    end
    count
  end

  def import_cci_entries(converter, data)
    count = 0
    Array(data["mappings"]).each do |entry|
      converter.converter_entries.create!(
        source_id: entry["cci"],
        target_id: entry["nist_rev5"] || entry["nist_rev4"],
        relationship: "equal",
        category: "cci",
        remarks: entry["status"]
      )
      count += 1
    end
    count
  end

  def import_cis_entries(converter, data)
    count = 0
    # Controls mappings (with relationship)
    Hash(data["controls_mappings"]).each do |cis_id, targets|
      Array(targets).each do |target|
        nist = target.is_a?(Hash) ? target["nist"] : target
        rel = target.is_a?(Hash) ? normalize_relationship(target["relationship"]) : "intersects"
        converter.converter_entries.create!(
          source_id: cis_id,
          target_id: nist,
          relationship: rel,
          category: "controls"
        )
        count += 1
      end
    end
    # Benchmark mappings
    Hash(data["benchmark_mappings"]).each do |section, targets|
      Array(targets).each do |nist|
        converter.converter_entries.create!(
          source_id: section,
          target_id: nist,
          relationship: "intersects",
          category: "benchmark"
        )
        count += 1
      end
    end
    count
  end

  def import_scap_entries(converter, data)
    count = 0
    # Check system mappings
    Array(data["check_system_mappings"]).each do |entry|
      Array(entry["nist_controls"]).each do |nist|
        converter.converter_entries.create!(
          source_id: entry["check_system"] || entry["label"],
          target_id: nist,
          relationship: normalize_relationship(entry["relationship"]),
          category: "check_system"
        )
        count += 1
      end
    end
    # OVAL test type mappings
    Array(data["oval_test_type_mappings"]).each do |entry|
      Array(entry["nist_controls"]).each do |nist|
        converter.converter_entries.create!(
          source_id: entry["test_type"],
          target_id: nist,
          relationship: normalize_relationship(entry["relationship"]),
          category: "oval_test_type",
          remarks: entry["description"]
        )
        count += 1
      end
    end
    # OVAL family mappings
    Hash(data["oval_family_mappings"]).each do |family, targets|
      Array(targets).each do |nist|
        converter.converter_entries.create!(
          source_id: family,
          target_id: nist,
          relationship: "intersects",
          category: "oval_family"
        )
        count += 1
      end
    end
    # Keyword mappings
    Hash(data["keyword_mappings"]).each do |category, mapping|
      Array(mapping["nist_controls"]).each do |nist|
        converter.converter_entries.create!(
          source_id: category,
          target_id: nist,
          relationship: "intersects",
          category: "keyword",
          remarks: Array(mapping["keywords"]).first(5).join(", ")
        )
        count += 1
      end
    end
    count
  end

  def import_generic_entries(converter, data)
    count = 0
    Array(data["mappings"] || data["entries"]).each do |entry|
      converter.converter_entries.create!(
        source_id: entry["source_id"] || entry["source"],
        target_id: entry["target_id"] || entry["target"],
        relationship: normalize_relationship(entry["relationship"]),
        category: entry["category"],
        remarks: entry["remarks"]
      )
      count += 1
    end
    count
  end

  def normalize_relationship(rel)
    return "intersects" if rel.blank?
    cleaned = rel.to_s.gsub(/-of$/, "").gsub("-", "_").downcase
    ConverterEntry::RELATIONSHIPS.include?(cleaned) ? cleaned : "intersects"
  end

  # Build export JSON from a converter
  def build_export_json(converter)
    entries = converter.converter_entries.to_a
    {
      "format" => "converter_mapping",
      "name" => converter.name,
      "converter_type" => converter.converter_type,
      "version" => converter.version,
      "description" => converter.description,
      "source_framework" => converter.source_framework,
      "target_framework" => converter.target_framework,
      "total_entries" => entries.size,
      "exported_at" => Time.current.iso8601,
      "entries" => entries.map { |e|
        {
          "source_id" => e.source_id,
          "target_id" => e.target_id,
          "relationship" => e.relationship,
          "category" => e.category,
          "remarks" => e.remarks
        }.compact
      }
    }
  end
end
