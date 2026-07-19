import { Controller } from "@hotwired/stimulus"

// Upper bound on how much of a rule <description> is fed to the tag-strip
// regex. The displayed description is truncated to 300 chars regardless, so
// this only caps pathological input. See the use site for the measurements.
const DESC_SCAN_LIMIT = 5000

/**
 * Client-side STIG XCCDF parser for instant preview and analysis.
 *
 * Parses DISA STIG XML files in the browser using DOMParser, extracts
 * SV/V-IDs, severity, CCIs, and resolves CCI→NIST controls. Provides
 * filtering, search, and CSV/JSON export.
 *
 * The "Import to SPARC" action submits the file server-side for
 * persistent storage as a Converter.
 */
export default class StigParserController extends Controller {
  static targets = [
    "resultsSection", "summaryTotal", "summaryHigh", "summaryMedium",
    "summaryLow", "summaryCci", "benchmarkTitle", "severityFilter",
    "cciToggle", "searchInput", "tableBody", "resultCount",
    "importForm", "importFileInput", "loading", "errorMessage"
  ]

  connect() {
    this.rules = []
    this.cciMap = {}
    this.currentFilter = "all"
    this.loadCciMap()
  }

  // ── CCI-to-NIST lookup ──────────────────────────────────────────

  async loadCciMap() {
    try {
      const response = await fetch("/data/cci_to_nist.json")
      if (!response.ok) return
      const data = await response.json()
      if (data.mappings) {
        for (const entry of data.mappings) {
          const cci = (entry.cci || "").toUpperCase()
          const nist = entry.nist_rev5 || entry.nist_rev4
          if (cci && nist) this.cciMap[cci] = nist
        }
      }
    } catch (e) {
      console.warn("STIG Parser: Could not load CCI map", e)
    }
  }

  // ── File handling (connected to dropzone via custom event) ──────

  handleFile(event) {
    const file = event.detail?.file
    if (!file) return

    this.clearResults()
    if (this.hasLoadingTarget) this.loadingTarget.classList.remove("d-none")
    if (this.hasErrorMessageTarget) this.errorMessageTarget.classList.add("d-none")

    // Store file reference for import
    this._file = file

    const reader = new FileReader()
    reader.onload = (e) => {
      try {
        this.parseSTIG(e.target.result)
      } catch (err) {
        this.showError(err.message)
      } finally {
        if (this.hasLoadingTarget) this.loadingTarget.classList.add("d-none")
      }
    }
    reader.onerror = () => {
      this.showError("Failed to read file.")
      if (this.hasLoadingTarget) this.loadingTarget.classList.add("d-none")
    }
    reader.readAsText(file)
  }

  // ── XCCDF Parser ────────────────────────────────────────────────

  parseSTIG(xmlString) {
    const parser = new DOMParser()
    const doc = parser.parseFromString(xmlString, "application/xml")

    const parseError = doc.querySelector("parsererror")
    if (parseError) throw new Error("Invalid XML: " + parseError.textContent.slice(0, 120))

    const benchmark = this.qsel(doc, "Benchmark")[0]
    if (!benchmark) throw new Error("No <Benchmark> element found in XCCDF file.")

    const titleEl = this.qsel(benchmark, "title")[0]
    const benchmarkTitle = titleEl?.textContent?.trim() || "Unknown STIG"

    this.rules = []
    const ruleEls = [...this.qsel(doc, "Rule")]

    for (const rule of ruleEls) {
      const ruleId = rule.getAttribute("id") || ""
      const severity = rule.getAttribute("severity") || ""

      // V-ID from <version> element
      const versionEl = this.qsel(rule, "version")[0]
      let vulnId = versionEl?.textContent?.trim() || ""

      const svMatch = ruleId.match(/(SV-\d+r?\d*)/i)
      const vMatch = vulnId.match(/(V-\d+)/i) || ruleId.match(/(V-\d+)/i)

      const svId = svMatch ? svMatch[1] : ""
      const vId = vMatch ? vMatch[1] : ""

      if (!svId && !vId) continue

      // CCI references
      const ccis = []
      const idents = [...this.qsel(rule, "ident")]
      for (const ident of idents) {
        const system = ident.getAttribute("system") || ""
        const text = ident.textContent.trim()
        if (system.includes("CCI") || text.match(/^CCI-/i)) {
          ccis.push(text.toUpperCase())
        }
      }

      // Resolve CCIs → NIST controls
      const nistControls = []
      for (const cci of ccis) {
        const nist = this.cciMap[cci]
        if (nist && !nistControls.includes(nist)) {
          nistControls.push(nist)
        }
      }

      // Title and description
      const title = this.qsel(rule, "title")[0]?.textContent?.trim() || ""
      const descRaw = this.qsel(rule, "description")[0]?.textContent?.trim() || ""
      // Bound the input before the tag-strip. `<[^>]+>` is O(n^2) on a long
      // run of '<' with no closing '>' (measured: 20k chars ~157ms, 50k
      // ~950ms), which a hostile STIG file could use to freeze the tab.
      // The result is truncated to 300 chars anyway, so capping the input
      // costs nothing. (javascript:S8786)
      const desc = descRaw
        .slice(0, DESC_SCAN_LIMIT)
        .replace(/<[^>]+>/g, " ")
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, 300)

      this.rules.push({ ruleId, svId, vId, severity, ccis, nistControls, title, desc })
    }

    if (this.rules.length === 0) {
      throw new Error("No STIG rules with V/SV IDs found. Verify this is a valid XCCDF STIG file.")
    }

    // Show results
    this.benchmarkTitleTarget.textContent = benchmarkTitle
    this.updateStats()
    this.renderTable()
    this.resultsSectionTarget.classList.remove("d-none")
  }

  // ── Namespace-aware element selection ────────────────────────────

  qsel(el, tag) {
    // These are XCCDF XML *namespace identifiers* declared by the parsed STIG
    // document — opaque strings matched against the DOM, never fetched over the
    // network. They MUST equal the exact literals NIST minted (http, not https),
    // or getElementsByTagNameNS stops matching. So javascript:S5332 ("use https")
    // is a false positive here and is suppressed inline.
    const namespaces = [
      "http://checklists.nist.gov/xccdf/1.2", // NOSONAR(javascript:S5332) XCCDF namespace URI, not a URL
      "http://checklists.nist.gov/xccdf/1.1", // NOSONAR(javascript:S5332) XCCDF namespace URI, not a URL
      "http://checklists.nist.gov/xccdf/1.0"  // NOSONAR(javascript:S5332) XCCDF namespace URI, not a URL
    ]
    for (const ns of namespaces) {
      const r = el.getElementsByTagNameNS(ns, tag)
      if (r.length) return [...r]
    }
    return [...el.getElementsByTagName(tag)]
  }

  // ── Stats ────────────────────────────────────────────────────────

  updateStats() {
    const rules = this.rules
    this.summaryTotalTarget.textContent = rules.length
    this.summaryHighTarget.textContent = rules.filter(r => r.severity === "high").length
    this.summaryMediumTarget.textContent = rules.filter(r => r.severity === "medium").length
    this.summaryLowTarget.textContent = rules.filter(r => r.severity === "low").length
    this.summaryCciTarget.textContent = rules.filter(r => r.ccis.length > 0).length
  }

  // ── Filtering ────────────────────────────────────────────────────

  filterBySeverity(event) {
    // Update active state on buttons
    this.severityFilterTargets.forEach(btn => btn.classList.remove("active"))
    event.currentTarget.classList.add("active")
    this.currentFilter = event.currentTarget.dataset.severity || "all"
    this.renderTable()
  }

  filterByCci() {
    this.renderTable()
  }

  search() {
    this.renderTable()
  }

  getFilteredRules() {
    let filtered = this.rules

    if (this.currentFilter !== "all") {
      filtered = filtered.filter(r => r.severity === this.currentFilter)
    }

    if (this.hasCciToggleTarget && this.cciToggleTarget.checked) {
      filtered = filtered.filter(r => r.ccis.length > 0)
    }

    if (this.hasSearchInputTarget && this.searchInputTarget.value.trim()) {
      const q = this.searchInputTarget.value.trim().toLowerCase()
      filtered = filtered.filter(r =>
        r.vId.toLowerCase().includes(q) ||
        r.svId.toLowerCase().includes(q) ||
        r.title.toLowerCase().includes(q) ||
        r.ccis.some(c => c.toLowerCase().includes(q)) ||
        r.nistControls.some(n => n.toLowerCase().includes(q))
      )
    }

    return filtered
  }

  // ── Table rendering ──────────────────────────────────────────────

  renderTable() {
    const filtered = this.getFilteredRules()
    this.resultCountTarget.textContent = `Showing ${filtered.length} of ${this.rules.length} rules`

    if (filtered.length === 0) {
      this.tableBodyTarget.innerHTML = `
        <tr><td colspan="6" class="text-center text-body-tertiary py-4">
          No rules match current filters.
        </td></tr>`
      return
    }

    const rows = filtered.map((r, i) => {
      const [sevClass, sevLabel] = { high: [ "high", "HIGH" ], medium: [ "medium", "MED" ] }[r.severity] || [ "low", "LOW" ]

      const cciBadges = r.ccis.length
        ? r.ccis.map(c => `<span class="sparc-stig-cci">${this.escapeHtml(c)}</span>`).join("")
        : `<span class="text-body-tertiary">&mdash;</span>`

      const nistBadges = r.nistControls.length
        ? r.nistControls.map(n => `<span class="sparc-stig-nist">${this.escapeHtml(n)}</span>`).join("")
        : `<span class="text-body-tertiary">&mdash;</span>`

      return `
        <tr data-action="click->stig-parser#toggleRow" data-rule-id="${this.escapeHtml(r.ruleId)}">
          <td><span class="sparc-stig-severity sparc-stig-severity--${sevClass}">${sevLabel}</span></td>
          <td class="text-nowrap" style="color: var(--sparc-warning); font-family: monospace; font-size: 0.82rem;">${this.escapeHtml(r.vId) || "&mdash;"}</td>
          <td class="text-nowrap" style="color: var(--sparc-primary); font-family: monospace; font-size: 0.82rem;">${this.escapeHtml(r.svId) || "&mdash;"}</td>
          <td>${cciBadges}</td>
          <td>${nistBadges}</td>
          <td class="text-truncate" style="max-width: 300px;">${this.escapeHtml(r.title)}</td>
        </tr>`
    }).join("")

    this.tableBodyTarget.innerHTML = rows
  }

  toggleRow(event) {
    const tr = event.currentTarget
    const ruleId = tr.dataset.ruleId
    const existing = tr.nextElementSibling
    if (existing && existing.classList.contains("sparc-stig-detail")) {
      existing.remove()
      return
    }

    const rule = this.rules.find(r => r.ruleId === ruleId)
    if (!rule) return

    const descEllipsis = rule.desc && rule.desc.length >= 300 ? "&hellip;" : ""

    const detailRow = document.createElement("tr")
    detailRow.classList.add("sparc-stig-detail")
    detailRow.innerHTML = `
      <td colspan="6" class="sparc-stig-detail">
        <div class="sparc-stig-detail__label">RULE ID</div>
        <div style="font-family: monospace; font-size: 0.82rem; margin-bottom: 0.75rem;">${this.escapeHtml(rule.ruleId)}</div>
        ${rule.desc ? `
          <div class="sparc-stig-detail__label">DESCRIPTION</div>
          <div style="font-size: 0.85rem; line-height: 1.6; max-width: 760px;">${this.escapeHtml(rule.desc)}${descEllipsis}</div>
        ` : ""}
      </td>`
    tr.after(detailRow)
  }

  // ── Export ───────────────────────────────────────────────────────

  exportCsv() {
    const filtered = this.getFilteredRules()
    const header = ["Rule ID", "V-ID", "SV-ID", "Severity", "CCIs", "NIST Controls", "Title"]
    const rows = filtered.map(r => [
      r.ruleId, r.vId, r.svId, r.severity,
      r.ccis.join("|"),
      r.nistControls.join("|"),
      `"${r.title.replaceAll('"', '""')}"`
    ])

    const csv = [header.join(","), ...rows.map(r => r.join(","))].join("\n")
    this.downloadFile(csv, "stig-parsed.csv", "text/csv")
  }

  exportJson() {
    const filtered = this.getFilteredRules()
    const json = JSON.stringify(filtered, null, 2)
    this.downloadFile(json, "stig-parsed.json", "application/json")
  }

  downloadFile(content, filename, mime) {
    const a = document.createElement("a")
    a.href = URL.createObjectURL(new Blob([content], { type: mime }))
    a.download = filename
    a.click()
    URL.revokeObjectURL(a.href)
  }

  // ── Import to SPARC ──────────────────────────────────────────────

  importToSparc() {
    if (!this._file) return

    // Copy file to hidden import form
    const dt = new DataTransfer()
    dt.items.add(this._file)
    this.importFileInputTarget.files = dt.files
    this.importFormTarget.submit()
  }

  // ── Helpers ──────────────────────────────────────────────────────

  clearResults() {
    this.rules = []
    this.currentFilter = "all"
    if (this.hasResultsSectionTarget) this.resultsSectionTarget.classList.add("d-none")
    if (this.hasTableBodyTarget) this.tableBodyTarget.innerHTML = ""
  }

  showError(message) {
    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.textContent = message
      this.errorMessageTarget.classList.remove("d-none")
    }
  }

  escapeHtml(str) {
    if (!str) return ""
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }
}
