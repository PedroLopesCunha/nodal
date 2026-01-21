import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.sortable = new Sortable(this.element, {
      handle: ".cursor-grab, .fa-grip-vertical",
      animation: 150,
      ghostClass: "bg-primary-subtle",
      onEnd: this.handleDragEnd.bind(this)
    })
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
    }
  }

  handleDragEnd() {
    const ids = Array.from(this.element.children).map(
      row => row.dataset.sortableId
    )

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      body: JSON.stringify({ attribute_ids: ids })
    }).catch(error => {
      console.error("Error reordering:", error)
    })
  }
}
