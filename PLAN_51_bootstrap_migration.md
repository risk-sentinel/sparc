# Implementation Plan: Issue #51 - Adopt Bootstrap CSS Framework

**Branch:** `feature/51_bootstrap_css_framework`
**Assignee:** jc3-sys

---

## Current State Analysis

- **46 ERB view files** across the app
- **327+ inline `style=` attributes** (grid, flex, colors, spacing)
- **31 custom CSS variables** for theming (light/dark mode)
- **Custom classes:** `.btn`, `.card`, `.badge-*`, `.form-group`, `.form-control`, `.flash`, `.navbar`, `.container`
- **2 layout files:** `application.html.erb` (main) and `login.html.erb` (auth)
- **Empty `application.css`** — all CSS is inline in layouts
- **Propshaft + Importmap** — no Node/Webpack build step
- **Stimulus controllers** already in use (flash_controller.js)

---

## Phase 1 — Add Bootstrap 5.3 via CDN + Theme Toggle

**Files:** `app/views/layouts/application.html.erb`, `app/views/layouts/login.html.erb`

1. Add Bootstrap 5.3 CSS CDN `<link>` to `<head>` in both layouts
2. Add Bootstrap 5.3 JS bundle CDN `<script>` before `</body>` in both layouts
3. Change `data-theme` on `<html>` to `data-bs-theme` (Bootstrap native dark mode)
4. Update `toggleTheme()` JS to set `data-bs-theme` instead of `data-theme`
5. Update `localStorage` key logic to use `data-bs-theme`
6. Update early flash-prevention script to use `data-bs-theme`

**Validation:** Dark/light toggle still works, Bootstrap CSS loads, no visual regression

---

## Phase 2 — Migrate Layout Global Styles

**Files:** `app/views/layouts/application.html.erb` (lines 9-342 inline `<style>` block)

### Class Mapping (Custom -> Bootstrap)

| Custom Class | Bootstrap Equivalent |
|---|---|
| `.btn` | `.btn` (same name, Bootstrap handles it) |
| `.btn-primary` | `.btn.btn-primary` |
| `.btn-success` | `.btn.btn-success` |
| `.btn-danger` | `.btn.btn-danger` |
| `.btn-secondary` | `.btn.btn-secondary` |
| `.card` | `.card .card-body` |
| `.badge-ok` | `.badge.bg-success` |
| `.badge-warn` | `.badge.bg-warning.text-dark` |
| `.badge-fail` | `.badge.bg-danger` |
| `.form-group` | `.mb-3` |
| `.form-group label` | `.form-label` |
| `.form-control` | `.form-control` (same name) |
| `.flash.success` | `.alert.alert-success` |
| `.flash.error` | `.alert.alert-danger` |
| `.flash.warning` | `.alert.alert-warning` |
| `.flash-container` | `.toast-container.position-fixed.top-0.end-0` |
| `.navbar` | `.navbar.navbar-dark.bg-dark` |
| `.container` | `.container` (same name) |
| `table` | `.table` |
| `th` (alt bg) | `.table .thead-light` / `.table-striped` |

### Actions:
1. Remove custom `.btn`, `.card`, `.badge-*`, `.form-*`, `.flash`, `.navbar`, `.container`, `table` styles from inline `<style>`
2. Keep only custom overrides that Bootstrap doesn't cover (gradient headers, heatmap cells, editor styles)
3. Move remaining custom CSS to `app/assets/stylesheets/application.css`
4. Update navbar HTML to use Bootstrap navbar component structure

---

## Phase 3 — Update View Files (46 files)

### 3a. Button Classes
**Find:** `class="btn btn-primary"` etc. (already matching Bootstrap names)
**Action:** Verify all `.btn` usage works with Bootstrap — may need to add `.btn` base class where missing

### 3b. Badge Classes
**Find/Replace across views:**
- `.badge-ok` -> `.badge bg-success`
- `.badge-warn` -> `.badge bg-warning text-dark`
- `.badge-fail` -> `.badge bg-danger`

### 3c. Form Classes
**Find/Replace:**
- `.form-group` -> `.mb-3`
- Add `.form-label` to all `<label>` elements in forms
- Verify `.form-control` still works (Bootstrap uses same name)

### 3d. Flash/Alert Classes
- Update flash partial to use `.alert .alert-dismissible` with Bootstrap dismiss button
- Update `flash_controller.js` if needed

### 3e. Table Classes
- Add `.table` class to all `<table>` elements
- Add `.table-striped` or `.table-hover` as appropriate

### 3f. Inline Style Replacement (327+ instances)
Priority replacements:
- `display: flex; justify-content: space-between; align-items: center` -> `d-flex justify-content-between align-items-center`
- `display: flex; gap: 0.5rem` -> `d-flex gap-2`
- `display: grid; grid-template-columns: repeat(3, 1fr); gap: 1.5rem` -> `row row-cols-1 row-cols-md-3 g-4`
- `margin-bottom: 1.5rem` -> `mb-4`
- `padding: 1rem` -> `p-3`
- `font-weight: 600` -> `fw-semibold`
- `font-size: 0.9rem` -> `small` or `fs-6`
- `text-align: center` -> `text-center`
- `color: var(--text-muted)` -> `text-body-secondary`
- `background: var(--surface-alt)` -> `bg-body-secondary`

### 3g. Color Variable Replacement
- `var(--text)` -> Bootstrap handles via `data-bs-theme`
- `var(--text-muted)` -> `text-body-secondary`
- `var(--bg)` -> `bg-body`
- `var(--surface)` -> `bg-body-tertiary`
- `var(--border)` -> `border`
- `var(--link-accent)` -> `text-primary` or keep as custom override

---

## Phase 4 — Migrate Login Layout

**File:** `app/views/layouts/login.html.erb`

1. Add Bootstrap CDN links (same as Phase 1)
2. Replace custom `.login-wrapper`, `.login-card`, `.login-header` with Bootstrap card/container
3. Replace `.login-tabs` with Bootstrap nav-tabs
4. Replace `.login-form-group` with Bootstrap `.mb-3` + `.form-label` + `.form-control`
5. Replace `.login-btn-primary` with `.btn.btn-primary.w-100`
6. Replace `.login-btn-oidc` with `.btn.btn-outline-secondary.w-100`
7. Replace `.login-divider` with custom Bootstrap-compatible divider
8. Remove inline `<style>` block

---

## Phase 5 — Remove Custom CSS Variables

1. Remove all `--btn-*`, `--badge-*`, `--link-*` custom properties
2. Remove all `--bg`, `--surface`, `--surface-alt`, `--border`, `--text` variables
3. Remove all `--flash-*` variables
4. Remove the `:root` and `[data-theme="dark"]` blocks entirely
5. Bootstrap's `data-bs-theme="dark"` handles all color mode switching natively

---

## Phase 6 — Custom Overrides in application.css

Move to `app/assets/stylesheets/application.css`:
- Gradient headers on show pages (`linear-gradient(135deg, #2c3e50 0%, #3498db 100%)`)
- Heatmap cell styles (`.heatmap-cell`)
- Editor-specific styles (`.conversion-section`, `.upload-container`, etc.)
- Summary chip styles (`.summary-chip`)
- Card-details expand/collapse styles
- Any Bootstrap overrides for project-specific branding

---

## Pre-PR Checks

### Rubocop (Ruby Linter)
```bash
bundle exec rubocop --autocorrect
# Fix any remaining issues that can't be auto-corrected
bundle exec rubocop
```

### Brakeman (Security Scanner)
```bash
bundle exec brakeman
# Review and fix any security warnings
```

---

## Files Changed (Estimated)

| Category | Files | Count |
|---|---|---|
| Layouts | `application.html.erb`, `login.html.erb` | 2 |
| Views | All `app/views/**/*.html.erb` | ~44 |
| Stylesheets | `application.css` | 1 |
| JavaScript | `flash_controller.js` (if needed) | 0-1 |
| **Total** | | **~47** |

---

## Considerations

- Bootstrap adds ~25KB CSS (gzipped) via CDN — acceptable for internal tool
- Class name migration is mostly mechanical (find/replace)
- Custom gradient headers need Bootstrap override classes
- Editor page has complex inline styles — migrate carefully
- No Node/npm needed — CDN + Propshaft + Importmap stays unchanged
- Existing Stimulus controllers remain unchanged (except possibly flash)
