# #935 — persist the compliance framework a catalog or baseline belongs to, so
# the index screens and their Api::V1 endpoints can filter by it.
#
# Nullable on purpose: FrameworkDeriver returns nil when no signal says clearly,
# and a null renders as "Unspecified", which is honest. A guess is not — the
# reason this was cut from #908 rather than shipped as a title regex evaluated
# per request.
#
# Indexed because the only thing it is for is filtering.
class AddFrameworkToCatalogsAndProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :control_catalogs,  :framework, :string
    add_column :profile_documents, :framework, :string

    add_index :control_catalogs,  :framework
    add_index :profile_documents, :framework
  end
end
