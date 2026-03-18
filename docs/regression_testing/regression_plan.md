# Regression testing

The goal of regressin testing is to validate that all functions are working
from end-to-end. These tests should be automated to the fullest extent possible
and performed prior to each release.

Testing files are kept in: [Sample Files](../../spec/fixtures/files/)

## Catalogs

Catalogs are the base for all files and will feed nearly all downstream functions.
The primary value of catalogs being to upload from existing frameworks that can
be tailored into a fully resolved profile that addresses the systems baseline controls.
A user could build a Catalog from scratch if they desired; however, this is not
part of the regression testing at this time.

- Upload
  - NIST (legacy)
    - XML
    - JSON
  - OSCAL
    - XML
    - YAML
    - JSON
- Export
  - NIST (legacy)
    - XML
    - JSON
  - OSCAL
    - XML
    - YAML
    - JSON

## Baseline / Profile

- Upload OSCAL
  - XML
  - YAML
  - JSON
- Import from Catalog
  - OSCAL
    - Rev 4
      - XML
      - JSON
      - YAML
    - Rev 5
      - XML
      - JSON
      - YAML
  - Legacy
    - Rev 4
      - XML
      - JSON
    - Rev 5
      - XML
      - JSON
- Update Parameters
- Update Priority
- Publish
  - OSCAL
    - Rev 4
      - XML
      - JSON
      - YAML
    - Rev 5
      - XML
      - JSON
      - YAML
  - Legacy
    - Rev 4
      - XML
      - JSON
    - Rev 5
      - XML
      - JSON
- Upload Fully resolved OSCAL
  - Rev 4
    - Low
    - Moderate
    - High
  - Rev 5
    - Low
    - Moderate
    - High

## System Security Plan

## Component Definition (CDEF)

## Security Assessment Plan (SAP)

## Security Assessment Results (SAR)

## Plan of Action & Milestones (POA&M)

## Evidence
