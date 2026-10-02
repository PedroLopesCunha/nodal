import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mode", "categories", "categoriesWrapper"]

  connect() { this.update() }

  changed() { this.dispatch("change") }

  update() {
    const all = this.modeTarget.value === "all"
    this.categoriesWrapperTarget.classList.toggle("d-none", all)
    if (all) {
      if (this.categoriesTarget.tomselect) this.categoriesTarget.tomselect.clear()
      else Array.from(this.categoriesTarget.options).forEach(option => { option.selected = false })
    }
    this.changed()
  }
}
