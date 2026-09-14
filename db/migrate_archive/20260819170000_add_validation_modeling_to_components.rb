# #998 — `validation` was an allowed component type and nothing could say what a
# validation component validates.
#
# OSCAL models third-party product validation (FIPS 140-2 and its kin) as a
# component PAIR: the product, and a second component of type `validation`
# carrying `validation-type` / `validation-reference` props and a
# `validation-details` link to the authoritative record, joined by a link with
# `rel="validation"` from the product to the validation. The pairing is the
# point — the certificate is an assertion ABOUT a component, made by someone
# else, so OSCAL gives it its own subject rather than a property.
#
# SPARC had the enum value and none of the rest: `validation-type` and
# `validation-reference` appeared nowhere in app/, and selecting `validation`
# produced a component OSCAL would accept and no consumer could act on.
#
# Modelled as first-class columns rather than free-form props so a certificate
# reference is checkable rather than typed, and so the pairing is a foreign key
# rather than a string a typo can break.
#
# CDEF gets props/links on its component instead of these fields: it exports
# exactly ONE component, built from the cdef_documents.component_* columns, so
# it cannot carry a pair at all. That asymmetry is deliberate and documented.
class AddValidationModelingToComponents < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:ssp_components, :validation_type)
      add_column :ssp_components, :validation_type, :string
    end

    unless column_exists?(:ssp_components, :validation_reference)
      add_column :ssp_components, :validation_reference, :string
    end

    unless column_exists?(:ssp_components, :validation_details_href)
      add_column :ssp_components, :validation_details_href, :string
    end

    # The product this validation is about. Nullable on purpose: a validation
    # component may be recorded before the product component it belongs to
    # exists, and refusing that would make the order of entry a rule.
    unless column_exists?(:ssp_components, :validates_component_id)
      add_column :ssp_components, :validates_component_id, :bigint
      add_index :ssp_components, :validates_component_id, if_not_exists: true
    end

    # #998 — the CDEF exporter emitted no props or links on its component at
    # all, so an imported CDEF's component-level claims were dropped on the way
    # back out. Props and links were already emitted on implemented-requirements
    # and statements; this is the one place they were missing.
    unless column_exists?(:cdef_documents, :component_props_data)
      add_column :cdef_documents, :component_props_data, :jsonb, default: []
    end

    unless column_exists?(:cdef_documents, :component_links_data)
      add_column :cdef_documents, :component_links_data, :jsonb, default: []
    end
  end
end
