class CleanupV164MitreFallbackRows < ActiveRecord::Migration[8.1]
  # Issue #494 -- v1.6.4 shipped a composite aws_security_hub_to_nist
  # Converter with rows tagged category='mitre_fallback'. v1.6.5 splits
  # those into the new aws_config_to_nist Converter (MITRE-sourced) and
  # resolves the chain at import time, so the mitre_fallback rows in
  # aws_security_hub_to_nist are now stale.
  #
  # This migration removes them so a fresh db:seed creates the clean
  # split. aws_direct rows are left in place; if no aws_direct rows
  # exist either (fresh DB), the seed loader is the source of truth
  # and this migration is a no-op.
  def up
    converter = Converter.find_by(converter_type: "aws_security_hub_to_nist")
    return unless converter

    removed = converter.converter_entries.where(category: "mitre_fallback").delete_all
    if removed > 0
      say "[#494] Removed #{removed} stale mitre_fallback rows from aws_security_hub_to_nist Converter"
    end
  end

  def down
    # Re-seed via db:seed; mitre_fallback semantics no longer exist in
    # v1.6.5. Downgrading to v1.6.4 requires manual re-seed.
  end
end
