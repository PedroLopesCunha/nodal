import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="storefront-category-tree"
export default class extends Controller {
  static targets = ["item", "toggle", "children", "icon"]

  connect() {
    this.loadExpandedState()
  }

  toggle(event) {
    const button = event.currentTarget
    const item = button.closest(".category-tree-item")
    const children = item.querySelector(".category-children")
    const icon = button.querySelector(".toggle-icon")

    if (children) {
      const isExpanded = !children.classList.contains("collapsed")

      if (isExpanded) {
        children.classList.add("collapsed")
        icon.classList.remove("fa-minus")
        icon.classList.add("fa-plus")
        button.setAttribute("aria-expanded", "false")
      } else {
        children.classList.remove("collapsed")
        icon.classList.remove("fa-plus")
        icon.classList.add("fa-minus")
        button.setAttribute("aria-expanded", "true")
      }

      this.saveExpandedState()
    }
  }

  loadExpandedState() {
    const stored = localStorage.getItem("storefrontCategoryExpanded")
    if (stored) {
      const expandedIds = JSON.parse(stored)
      this.itemTargets.forEach(item => {
        const categoryId = item.dataset.categoryId
        const children = item.querySelector(".category-children")
        const icon = item.querySelector(".toggle-icon")
        const toggle = item.querySelector("[data-action*='toggle']")

        if (children) {
          if (expandedIds.includes(categoryId)) {
            children.classList.remove("collapsed")
            if (icon) {
              icon.classList.remove("fa-plus")
              icon.classList.add("fa-minus")
            }
            if (toggle) toggle.setAttribute("aria-expanded", "true")
          } else {
            children.classList.add("collapsed")
            if (icon) {
              icon.classList.remove("fa-minus")
              icon.classList.add("fa-plus")
            }
            if (toggle) toggle.setAttribute("aria-expanded", "false")
          }
        }
      })
    }
  }

  saveExpandedState() {
    const expandedIds = []
    this.itemTargets.forEach(item => {
      const children = item.querySelector(".category-children")
      if (children && !children.classList.contains("collapsed")) {
        expandedIds.push(item.dataset.categoryId)
      }
    })
    localStorage.setItem("storefrontCategoryExpanded", JSON.stringify(expandedIds))
  }
}
