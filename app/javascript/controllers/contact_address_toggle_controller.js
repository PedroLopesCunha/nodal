import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "addressFields"]

  toggle() {
    if (this.checkboxTarget.checked) {
      this.addressFieldsTarget.classList.add("d-none")
    } else {
      this.addressFieldsTarget.classList.remove("d-none")
    }
  }
}
