# Builds a new ControlCatalog, optionally pre-populated with standard
# NIST SP 800-53 control families.
#
# Usage:
#   # Blank catalog
#   catalog = CatalogBuilderService.new(name: "My Custom Catalog").build
#
#   # Pre-populated with NIST families
#   catalog = CatalogBuilderService.new(
#     name: "My NIST Catalog",
#     template: :nist_families
#   ).build
#
class CatalogBuilderService
  NIST_FAMILIES = [
    { code: "AC", name: "Access Control", sort_order: 1 },
    { code: "AT", name: "Awareness and Training", sort_order: 2 },
    { code: "AU", name: "Audit and Accountability", sort_order: 3 },
    { code: "CA", name: "Assessment, Authorization, and Monitoring", sort_order: 4 },
    { code: "CM", name: "Configuration Management", sort_order: 5 },
    { code: "CP", name: "Contingency Planning", sort_order: 6 },
    { code: "IA", name: "Identification and Authentication", sort_order: 7 },
    { code: "IR", name: "Incident Response", sort_order: 8 },
    { code: "MA", name: "Maintenance", sort_order: 9 },
    { code: "MP", name: "Media Protection", sort_order: 10 },
    { code: "PE", name: "Physical and Environmental Protection", sort_order: 11 },
    { code: "PL", name: "Planning", sort_order: 12 },
    { code: "PM", name: "Program Management", sort_order: 13 },
    { code: "PS", name: "Personnel Security", sort_order: 14 },
    { code: "PT", name: "Personally Identifiable Information Processing and Transparency", sort_order: 15 },
    { code: "RA", name: "Risk Assessment", sort_order: 16 },
    { code: "SA", name: "System and Services Acquisition", sort_order: 17 },
    { code: "SC", name: "System and Communications Protection", sort_order: 18 },
    { code: "SI", name: "System and Information Integrity", sort_order: 19 },
    { code: "SR", name: "Supply Chain Risk Management", sort_order: 20 }
  ].freeze

  TEMPLATES = %i[blank nist_families].freeze

  def initialize(name:, template: :blank, version: nil, source: nil, description: nil)
    @name = name
    @template = template.to_sym
    @version = version
    @source = source
    @description = description
  end

  def build
    ActiveRecord::Base.transaction do
      catalog = ControlCatalog.create!(
        name: @name,
        version: @version,
        source: @source,
        description: @description
      )

      create_families(catalog) if @template == :nist_families

      catalog
    end
  end

  private

  def create_families(catalog)
    NIST_FAMILIES.each do |family_attrs|
      catalog.control_families.create!(family_attrs)
    end
  end
end
