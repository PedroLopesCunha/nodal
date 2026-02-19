import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "attributesSection", "attributeCard", "valuesSection"]

  toggleAttributes() {
    const isEnabled = this.toggleTarget.checked

    if (this.hasAttributesSectionTarget) {
      this.attributesSectionTarget.style.display = isEnabled ? "block" : "none"
    }
  }

  toggleAttribute(event) {
    const checkbox = event.target
    const card = checkbox.closest("[data-variant-configuration-target='attributeCard']")
    const valuesSection = card.querySelector("[data-variant-configuration-target='valuesSection']")

    if (valuesSection) {
      if (checkbox.checked) {
        valuesSection.classList.remove("d-none")
      } else {
        valuesSection.classList.add("d-none")
        // Uncheck all value checkboxes when attribute is unchecked
        valuesSection.querySelectorAll("input[type='checkbox']").forEach(cb => {
          cb.checked = false
        })
      }
    }
  }

  filterValues(event) {
    const query = event.target.value.toLowerCase().trim()
    const card = event.target.closest("[data-variant-configuration-target='attributeCard']")
    const checkboxes = card.querySelectorAll(".form-check")

    checkboxes.forEach(item => {
      const label = item.querySelector(".form-check-label")
      if (!label) return
      const text = label.textContent.toLowerCase().trim()
      item.style.display = (!query || text.includes(query)) ? "" : "none"
    })
  }
}
