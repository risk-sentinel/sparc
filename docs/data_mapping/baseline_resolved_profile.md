# Baseline to Resolved Profile Relationship

This is a simple diagram showing the Primary Key (PK) and Foreign Key (FK)
Relationships of a Baseline (control list, priority, starting position)
with it's Resolved Profile contains the updated Metadata and Backmatter.
The Backmatter will contain the UUID of the source catalog with the available
types (JSON, YAML, XML).

```mermad
erDiagram
    PROFILE {
        string uuid PK
        object metadata
        array imports
        object merge
        object modify
        object back_matter
    }
    IMPORT {
        string href "references source catalog"
        array include_controls
    }
    INCLUDE_CONTROL {
        array with_ids "list of control IDs (FK to CONTROL.id)"
    }
    MODIFY {
        array alters
    }
    ALTER {
        string control_id FK "references CONTROL.id"
        array adds "adds props like priority"
    }
    RESOLVED_CATALOG {
        string uuid PK
        object metadata
        array groups
        object back_matter
    }
    GROUP {
        string id PK "family code e.g., 'ac'"
        string class
        string title
        array controls
    }
    CONTROL {
        string id PK "e.g., 'ac-1'"
        string class
        string title
        array params
        array props "includes added priority from ALTER"
        array links
        array parts "statement, guidance, etc."
    }
    PROFILE ||--o{ IMPORT : "defines imports from source catalog"
    IMPORT ||--|{ INCLUDE_CONTROL : "specifies controls to include"
    INCLUDE_CONTROL }|--|| CONTROL : "selects by id"
    PROFILE ||--|| MODIFY : "defines modifications"
    MODIFY ||--o{ ALTER : "contains alters for controls"
    ALTER ||--|| CONTROL : "modifies by control_id"
    RESOLVED_CATALOG ||--o{ GROUP : "organizes controls into families"
    GROUP ||--o{ CONTROL : "contains selected and modified controls"
    CONTROL ||--o{ PROP : "has properties (e.g., priority added)"
```
