# frozen_string_literal: true

# #1340 — the SSP Enrich page's save, checked as a whole before anything is
# written.
#
# The page saves the SSP's system fields and three repeated sections
# (information types, components, system users) in one submit. It used to
# write row by row and stop at the first refusal. The author got one message
# ("Title can't be blank, Description can't be blank") with no row named, and
# the page reloaded with their input gone. A row added and left blank was sent
# as "" and refused, because the `title || "Component"` fallbacks only covered
# a missing value.
#
# Now every row is built in memory and validated, all errors are collected
# with the row they belong to, and nothing is written unless all of it is
# valid. On failure the rows are handed back as built (the author's input
# kept, each record carrying its errors) so the page can be redrawn in place
# with each refused field marked.
#
# NIST SP 800-53 Rev 5: SI-10 (input validation: refused input is identified),
# PL-2 (the SSP's system characteristics).
class SspEnrichForm
  DOCUMENT_FIELDS = %i[
    description system_name_short system_id system_status date_authorized
    security_sensitivity_level security_objective_confidentiality
    security_objective_integrity security_objective_availability
    authorization_boundary_description network_architecture_description
    data_flow_description
  ].freeze

  INFO_TYPE_FIELDS = %i[title description confidentiality_impact_base integrity_impact_base
                        availability_impact_base].freeze
  # #998 — the validation pair. The model refuses these on a component that is
  # not a validation, rather than storing them somewhere no exporter looks.
  COMPONENT_FIELDS = %i[component_type title description status_state validation_type
                        validation_reference validation_details_href validates_component_id].freeze
  USER_FIELDS = %i[title description short_name].freeze

  # The text an author types into each kind of row. An added row with all of
  # these blank is reported, never saved as an empty row.
  TYPED_FIELDS = {
    information_types: %i[title description],
    components: %i[title description],
    users: %i[title description short_name]
  }.freeze

  SECTION_LABELS = { information_types: "Information type", components: "Component", users: "User" }.freeze
  EMPTY_ROW = "is empty: fill it in, or remove the row"

  attr_reader :document, :info_types, :components, :users

  # @param params [ActionController::Parameters] the whole request's params
  def initialize(document, params)
    @document = document
    @params = params.fetch(:ssp_document, ActionController::Parameters.new)
    @info_types = build_rows(:information_types, document.ssp_information_types, INFO_TYPE_FIELDS)
    @components = build_rows(:components, document.ssp_components, COMPONENT_FIELDS)
    @users = build_rows(:users, document.ssp_users, USER_FIELDS, extra: { role_ids_data: [] }, lists: { role_ids_data: [] })
  end

  # @return [Boolean] true when everything was valid and saved
  def save
    document.assign_attributes(@params.permit(*DOCUMENT_FIELDS))
    return false unless valid?

    ActiveRecord::Base.transaction do
      document.save!
      rows.each(&:save!)
      remove_unlisted!
    end
    true
  end

  # One line per refused field, naming its row: "Component 3: Title can't be blank".
  def error_messages
    lines = document.errors.full_messages.map { "System information: #{_1}" }
    { information_types: info_types, components: components, users: users }.each do |section, list|
      list.each_with_index do |row, index|
        row.errors.full_messages.each { lines << "#{SECTION_LABELS[section]} #{index + 1}: #{_1}" }
      end
    end
    lines
  end

  private

  def rows = info_types + components + users

  # Every record is validated, so every refused field is marked, not just the first.
  def valid?
    results = [ document.valid? ] + rows.map { |row| row.valid? }
    # The SSP also validates its new rows; each row reports its own errors.
    %i[ssp_information_types ssp_components ssp_users].each { document.errors.delete(_1) }
    results[0] = document.errors.empty?
    flag_empty_added_rows
    results.all? && rows.none? { _1.errors.any? }
  end

  def flag_empty_added_rows
    { information_types: info_types, components: components, users: users }.each do |section, list|
      list.each do |row|
        next if row.persisted?
        next unless TYPED_FIELDS[section].all? { row.public_send(_1).blank? }

        row.errors.clear
        row.errors.add(:title, EMPTY_ROW)
      end
    end
  end

  # The submitted rows, in the order the page showed them: an existing row is
  # loaded and given the submitted values, an added one is built. Nothing is
  # saved here.
  def build_rows(section, association, fields, extra: {}, lists: {})
    existing = association.index_by(&:id)
    Array(@params[section]).select { _1.respond_to?(:permit) }.map do |row_params|
      attrs = row_params.permit(:id, *fields, **lists).to_h.symbolize_keys
      id = attrs.delete(:id).presence&.to_i
      if id && existing[id]
        existing[id].tap { _1.assign_attributes(attrs) }
      else
        association.build({ uuid: SecureRandom.uuid }.merge(new_row_defaults(section)).merge(extra).merge(compact_blank_selects(attrs)))
      end
    end
  end

  # Choices that are never typed get their usual starting value when left at
  # the default. Typed text is never filled in.
  def new_row_defaults(section)
    section == :components ? { component_type: "software", status_state: "operational" } : {}
  end

  def compact_blank_selects(attrs)
    attrs.reject { |key, value| %i[component_type status_state].include?(key) && value.blank? }
  end

  # Rows the author removed from the page. "This system" components are never
  # on the form, so they are kept.
  def remove_unlisted!
    document.ssp_information_types.where.not(id: info_types.map(&:id)).delete_all
    document.ssp_components.where.not(id: components.map(&:id) + document.ssp_components.this_system.ids).delete_all
    document.ssp_users.where.not(id: users.map(&:id)).delete_all
  end
end
