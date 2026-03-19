# frozen_string_literal: true

class AddOrganizationIdToAuthorizationBoundaries < ActiveRecord::Migration[8.0]
  def change
    add_reference :authorization_boundaries, :organization, null: true, foreign_key: { on_delete: :nullify }
  end
end
