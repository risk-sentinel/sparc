# FedRAMP sample package

> **DEMO/SAMPLE DATA ONLY.** Everything here is fictional: the provider, the
> service, the assessor, the advisor, the agencies, every address and every
> phone number. Hosts are reserved `example.com` / `example.org` /
> `example.net` names (RFC 2606) and phone numbers are in the fictional
> `555-01xx` range.

A complete FedRAMP package for one fictional provider, **Example Cloud Works,
Inc.** (service *Example Case Manager*, FedRAMP ID `FR0000000001`). It has one
document for each FedRAMP package schema SPARC vendors
(`lib/data/fedramp/schemas/`, ruleset 2026-06-24). Every document names its
schema in `$schema`, and every report points at the package overview's
address, `https://trust.example.com/fedramp/certification-package-overview.json`.

Each document passes both of SPARC's checks with **zero errors**: it matches
its schema, and every field the schema requires is filled in. Three
documents leave out one optional field on purpose, so each shows one
warning. The reasons are in `manifest.json`.

## The documents

| File | FedRAMP rule | What it is | Warnings |
|---|---|---|---|
| `certification-package-overview.json` | FRC-CSO-PKG | The package overview: service, trust center, contacts, assessor, certified services. Carries the FedRAMP ID. | 1 (`ueiNumber`: a made-up UEI could be a real entity's) |
| `security-decision-record.json` | SDR-CSO-FRR | NIST SP 800-53 controls (AC-2, IA-2, RA-5) with Rev 5 parameter values, two FedRAMP requirements, and three Key Security Indicators (KSI-IAM-APM, KSI-MLA-LET, KSI-SVC-VRI) with tests and evidence | 0 |
| `ongoing-certification-report.json` | CCM-OCR-AVL | The quarterly report for August–October 2026 | 0 |
| `vulnerability-detail-report.json` | VER-RPT-VDT | Two vulnerabilities with N-ratings and PAIN reduction history | 1 (a remediated vulnerability has no next reduction) |
| `accepted-vulnerability-info.json` | VER-RPT-AVI | One accepted vulnerability and why it was accepted | 0 |
| `incident-report.json` | IEC-CSO-FIR | A Final incident report | 0 |
| `significant-change-notifications.json` | SCN-CSO-INF | A Transformative change with its plan and milestones | 0 |
| `historical-ver-activity.json` | VER-TFR-MRH | A snapshot of every active and accepted vulnerability | 0 |
| `assessor-information.json` | MKT-IAS-WEB | The assessor's marketplace information | 0 |
| `advisor-information.json` | MKT-CAS-WEB | The advisor's marketplace information | 1 (`a2laId`: advisors need no A2LA accreditation) |

## Invalid variants (`invalid/`)

Each file is a copy of a valid document broken in **one** way.
`invalid/manifest.json` lists the exact error each one must produce.

| File | What is wrong | Check | Pointer |
|---|---|---|---|
| `vdr-blank-required-field.json` | `vulnerabilityDescription` is only spaces | completeness | `/vulnerabilities/0/vulnerabilityDescription` |
| `sdr-missing-required-field.json` | `fedRampRequirements` is removed | schema | (the document root) |
| `cpo-bad-enum.json` | `certificationType` is `"Rev6"` | schema | `/serviceIdentification/certificationType` |
| `ocr-wrong-type.json` | `activeAgencies` is a string, not an array | schema | `/activeAgencies` |
| `incident-bad-date-time.json` | `timeline.detectedAt` is `"2026-09-14 03:20"` | schema | `/timeline/detectedAt` |

## Loading the package

**In the browser.** Open a boundary, go to **Evidence → Received documents**,
and drop the files on the upload card. Each valid document is stored as
**Pending review**. An invalid one is stored as **Invalid**, its errors are
shown, and it can never be accepted.

**Through the API.** Upload each file to the boundary's received documents:

```bash
curl -H "Authorization: Bearer $SPARC_TOKEN" \
  -F "file=@samples/fedramp-package-demo/vulnerability-detail-report.json" \
  "$SPARC_URL/api/v1/authorization_boundaries/$BOUNDARY_ID/received_documents"
```

To check a document without storing it, use `POST /api/v1/document_validations`.

**On a demo instance.** `SPARC_SEED_DEMO=true bin/rails db:seed` loads the
valid documents into the demo boundary, *Cloud Web Application ATO*, as
received documents waiting for review (seed section
`demo_fedramp_package_samples`). A second run stores nothing new.

## Where it is tested

- `spec/samples/fedramp_package_demo_spec.rb`: every valid document
  validates as its manifest says, and every invalid one fails with its
  listed error. Each is also received into a boundary and checked.
- `spec/seeds/fedramp_package_samples_spec.rb`: the demo seed.
- `tests/api/test_fedramp_sample_package.py`: uploads through the API.
- `tests/ui-smoke/test_fedramp_sample_package_1354.py`: uploads through the
  Received documents dropzone in Chrome.
