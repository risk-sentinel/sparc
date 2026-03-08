#!/usr/bin/env bash
# Creates GitHub issue labels for all 20 NIST SP 800-53 control families.
# Usage: ./scripts/create_nist_labels.sh

set -euo pipefail

labels=(
  "AC: Access Control|1f77b4|NIST 800-53 Access Control family"
  "AT: Awareness and Training|ff7f0e|NIST 800-53 Awareness and Training family"
  "AU: Audit and Accountability|2ca02c|NIST 800-53 Audit and Accountability family"
  "CA: Assessment and Authorization|d62728|NIST 800-53 Assessment, Authorization, and Monitoring family"
  "CM: Configuration Management|9467bd|NIST 800-53 Configuration Management family"
  "CP: Contingency Planning|8c564b|NIST 800-53 Contingency Planning family"
  "IA: Identification and Authentication|e377c2|NIST 800-53 Identification and Authentication family"
  "IR: Incident Response|7f7f7f|NIST 800-53 Incident Response family"
  "MA: Maintenance|bcbd22|NIST 800-53 Maintenance family"
  "MP: Media Protection|17becf|NIST 800-53 Media Protection family"
  "PE: Physical and Environmental Protection|aec7e8|NIST 800-53 Physical and Environmental Protection family"
  "PL: Planning|ffbb78|NIST 800-53 Planning family"
  "PM: Program Management|98df8a|NIST 800-53 Program Management family"
  "PS: Personnel Security|ff9896|NIST 800-53 Personnel Security family"
  "PT: PII Processing and Transparency|c5b0d5|NIST 800-53 PII Processing and Transparency family"
  "RA: Risk Assessment|c49c94|NIST 800-53 Risk Assessment family"
  "SA: System and Services Acquisition|f7b6d2|NIST 800-53 System and Services Acquisition family"
  "SC: System and Communications Protection|c7c7c7|NIST 800-53 System and Communications Protection family"
  "SI: System and Information Integrity|dbdb8d|NIST 800-53 System and Information Integrity family"
  "SR: Supply Chain Risk Management|9edae5|NIST 800-53 Supply Chain Risk Management family"
)

for entry in "${labels[@]}"; do
  IFS='|' read -r name color desc <<< "$entry"
  echo "Creating label: $name"
  gh label create "$name" --color "$color" --description "$desc" --force 2>&1 || echo "  Failed: $name"
done

echo "Done! Created ${#labels[@]} NIST control family labels."
