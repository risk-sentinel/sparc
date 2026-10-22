# End-to-end OSCAL samples

Sample documents for testing a SPARC instance by hand, all from one tailored
NIST SP 800-53 Rev 5 MODERATE baseline. SPARC's own pipeline produced them;
none were written by hand.

| File | What it is |
|---|---|
| `../profiles/NIST_SP-800-53_rev5_MODERATE-tailored_profile.json` | NIST's MODERATE profile with all 584 settable parameters set (`ac-01_odp.05` = `365`). Upload it as a baseline against the NIST Rev 5 catalog. |
| `ssp-nist-rev5-moderate-tailored.json` | The SSP built from that baseline: 287 controls, 110 enhancements, every statement part answered. Each answer is this system's by-component description. |
| `sap-nist-rev5-moderate-tailored.json` | The assessment plan: all 1,795 800-53A objectives, named in `control-objective-selections`. |
| `sar-nist-rev5-moderate-tailored.json` | The assessment results, with every determinable objective determined: most satisfied, every seventh not satisfied. |

All are valid OSCAL 1.2.3. `spec/integration/end_to_end_samples_spec.rb` checks them on every run.

To regenerate them:

```bash
ruby bin/generate_tailored_profile_fixture.rb          # the tailored profile
WRITE_E2E_SAMPLES=1 bundle exec rspec spec/integration/end_to_end_samples_spec.rb
```

`spec/integration/nist_moderate_end_to_end_spec.rb` follows the same baseline
through import, the SSP screen, export and re-import.
