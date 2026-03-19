# frozen_string_literal: true

# Full structural rename: Project → AuthorizationBoundary
#
# Renames tables, foreign key columns, and migrates stored data values
# (role scopes, permission keys) to align with NIST RMF terminology.
#
# Issue #124 — Rebrand "Project" to "Authorization Boundary"
class RenameProjectsToAuthorizationBoundaries < ActiveRecord::Migration[8.1]
  def up
    # ── Table renames ──────────────────────────────────────────────────────
    rename_table :projects, :authorization_boundaries
    rename_table :project_memberships, :authorization_boundary_memberships

    # ── FK column renames ──────────────────────────────────────────────────
    rename_column :authorization_boundary_memberships, :project_id, :authorization_boundary_id
    rename_column :boundaries, :project_id, :authorization_boundary_id
    rename_column :ssp_documents, :project_id, :authorization_boundary_id
    rename_column :sar_documents, :project_id, :authorization_boundary_id
    rename_column :sap_documents, :project_id, :authorization_boundary_id
    rename_column :poam_documents, :project_id, :authorization_boundary_id
    rename_column :evidences, :project_id, :authorization_boundary_id
    rename_column :user_roles, :project_id, :authorization_boundary_id

    # ── Data migration: role scope ─────────────────────────────────────────
    execute <<~SQL
      UPDATE roles SET scope = 'authorization_boundary' WHERE scope = 'project';
    SQL

    # ── Data migration: permission keys in JSONB ───────────────────────────
    # Rename "projects.read" → "authorization_boundaries.read", etc.
    execute <<~SQL
      UPDATE roles
      SET permissions = (
        permissions
        - 'projects.read' - 'projects.write' - 'projects.manage_members'
        || jsonb_build_object(
          'authorization_boundaries.read',           COALESCE(permissions->'projects.read', 'false'::jsonb),
          'authorization_boundaries.write',           COALESCE(permissions->'projects.write', 'false'::jsonb),
          'authorization_boundaries.manage_members',  COALESCE(permissions->'projects.manage_members', 'false'::jsonb)
        )
      )
      WHERE permissions ? 'projects.read'
         OR permissions ? 'projects.write'
         OR permissions ? 'projects.manage_members';
    SQL
  end

  def down
    # ── Reverse data migration: permission keys ────────────────────────────
    execute <<~SQL
      UPDATE roles
      SET permissions = (
        permissions
        - 'authorization_boundaries.read' - 'authorization_boundaries.write' - 'authorization_boundaries.manage_members'
        || jsonb_build_object(
          'projects.read',           COALESCE(permissions->'authorization_boundaries.read', 'false'::jsonb),
          'projects.write',           COALESCE(permissions->'authorization_boundaries.write', 'false'::jsonb),
          'projects.manage_members',  COALESCE(permissions->'authorization_boundaries.manage_members', 'false'::jsonb)
        )
      )
      WHERE permissions ? 'authorization_boundaries.read'
         OR permissions ? 'authorization_boundaries.write'
         OR permissions ? 'authorization_boundaries.manage_members';
    SQL

    # ── Reverse data migration: role scope ─────────────────────────────────
    execute <<~SQL
      UPDATE roles SET scope = 'project' WHERE scope = 'authorization_boundary';
    SQL

    # ── Reverse FK column renames ──────────────────────────────────────────
    rename_column :user_roles, :authorization_boundary_id, :project_id
    rename_column :evidences, :authorization_boundary_id, :project_id
    rename_column :poam_documents, :authorization_boundary_id, :project_id
    rename_column :sap_documents, :authorization_boundary_id, :project_id
    rename_column :sar_documents, :authorization_boundary_id, :project_id
    rename_column :ssp_documents, :authorization_boundary_id, :project_id
    rename_column :boundaries, :authorization_boundary_id, :project_id
    rename_column :authorization_boundary_memberships, :authorization_boundary_id, :project_id

    # ── Reverse table renames ──────────────────────────────────────────────
    rename_table :authorization_boundary_memberships, :project_memberships
    rename_table :authorization_boundaries, :projects
  end
end
