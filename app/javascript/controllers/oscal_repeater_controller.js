// Generic repeater for OSCAL extensibility arrays (props, links, etc.)
// rendered as repeating form rows. Used by the POAM item form for the
// `props_data` and `links_data` JSONB columns (#389).
//
// Markup contract:
//   <div data-controller="oscal-repeater">
//     <template data-oscal-repeater-target="template">
//       <div class="repeater-row"> ... fields ... </div>
//     </template>
//     <div data-oscal-repeater-target="rows">
//       <!-- existing rows -->
//     </div>
//     <button type="button" data-action="click->oscal-repeater#add">+ Add</button>
//   </div>
//
// Each row must include a remove button:
//   <button type="button" data-action="click->oscal-repeater#remove">×</button>
//
// Field input names use Rails' empty-bracket array notation, e.g.
// `poam_item[props_data][][name]`. Rails groups fields in input-emission
// order: first occurrence of any key starts a new hash, subsequent
// not-yet-set keys join that hash, repeated keys start the next.

import { Controller } from "@hotwired/stimulus"

export default class OscalRepeaterController extends Controller {
  static targets = ["template", "rows"]

  add(event) {
    event.preventDefault()
    const fragment = this.templateTarget.content.cloneNode(true)
    this.rowsTarget.appendChild(fragment)
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest(".repeater-row")
    if (row) row.remove()
  }
}
