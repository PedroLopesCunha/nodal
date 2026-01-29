import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Connects to data-controller="category-tree"
export default class extends Controller {
  static targets = ["list", "item", "handle", "toggle", "children"]
  static values = { url: String }

  connect() {
    this.initSortable()
    this.loadExpandedState()
  }

  initSortable() {
    // Initialize sortable on the root list
    this.initSortableOnList(this.listTarget)

    // Initialize sortable on all children lists
    this.childrenTargets.forEach(list => {
      this.initSortableOnList(list)
    })
  }

  initSortableOnList(list) {
    new Sortable(list, {
      group: "categories",
      handle: ".drag-handle",
      animation: 150,
      fallbackOnBody: true,
      swapThreshold: 0.65,
      ghostClass: "category-ghost",
      chosenClass: "category-chosen",
      dragClass: "category-drag",
      onEnd: this.handleDragEnd.bind(this)
    })
  }

  handleDragEnd(event) {
    const item = event.item
    const categoryId = item.dataset.id
    const newParentList = event.to
    const newPosition = event.newIndex

    // Determine the new parent_id
    let parentId = null
    const parentItem = newParentList.closest(".category-tree-item")
    if (parentItem) {
      parentId = parentItem.dataset.id
    }

    // Send update to server
    const url = this.urlValue.replace(":id", categoryId)
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      body: JSON.stringify({
        parent_id: parentId,
        position: newPosition
      })
    }).then(response => {
      if (!response.ok) {
        console.error("Failed to move category")
        // Could reload page or show error
      }
    }).catch(error => {
      console.error("Error moving category:", error)
    })
  }

  toggleChildren(event) {
    const button = event.currentTarget
    const item = button.closest(".category-tree-item")
    const children = item.querySelector(".category-children")
    const icon = button.querySelector(".toggle-icon")

    if (children) {
      children.classList.toggle("collapsed")
      icon.classList.toggle("rotated")
      this.saveExpandedState()
    }
  }

  loadExpandedState() {
    const stored = localStorage.getItem("categoryTreeExpanded")
    if (stored) {
      const expandedIds = JSON.parse(stored)
      this.itemTargets.forEach(item => {
        const categoryId = item.dataset.id
        const children = item.querySelector(".category-children")
        const icon = item.querySelector(".toggle-icon")

        if (children) {
          if (expandedIds.includes(categoryId)) {
            children.classList.remove("collapsed")
            if (icon) icon.classList.add("rotated")
          } else {
            children.classList.add("collapsed")
            if (icon) icon.classList.remove("rotated")
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
        expandedIds.push(item.dataset.id)
      }
    })
    localStorage.setItem("categoryTreeExpanded", JSON.stringify(expandedIds))
  }
}
