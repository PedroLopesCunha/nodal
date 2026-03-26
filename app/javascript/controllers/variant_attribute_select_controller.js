import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "inputWrapper", "input", "createBtn", "createName"]
  static values = { attributeId: Number }

  toggleInput() {
    if (this.selectTarget.value === "__new__") {
      this.inputWrapperTarget.style.display = ""
      this.inputTarget.focus()
    } else {
      this.inputWrapperTarget.style.display = "none"
      this.inputTarget.value = ""
      this.hideCreateBtn()
    }
  }

  onInput() {
    const val = this.inputTarget.value.trim().replace(/,/g, ".")
    if (val) {
      this.createBtnTarget.style.display = ""
      this.createNameTarget.textContent = val
    } else {
      this.hideCreateBtn()
    }
  }

  hideCreateBtn() {
    this.createBtnTarget.style.display = "none"
  }

  async create(event) {
    event.preventDefault()
    const newValue = this.inputTarget.value.trim().replace(/,/g, ".")
    if (!newValue) return

    const btn = this.createBtnTarget
    btn.disabled = true

    try {
      const orgSlug = window.location.pathname.split("/")[1]
      const csrfToken = document.querySelector("meta[name='csrf-token']").content
      const response = await fetch(`/${orgSlug}/bo/product_attributes/${this.attributeIdValue}/product_attribute_values`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify({ value: newValue })
      })

      if (response.ok) {
        const data = await response.json()

        // Add new option to select before the "__new__" option and select it
        const newOption = document.createElement("option")
        newOption.value = data.id
        newOption.textContent = data.value
        const newOpt = this.selectTarget.querySelector('option[value="__new__"]')
        this.selectTarget.insertBefore(newOption, newOpt)
        this.selectTarget.value = data.id

        // Hide input wrapper and button
        this.inputWrapperTarget.style.display = "none"
        this.inputTarget.value = ""
        this.hideCreateBtn()
      } else {
        const data = await response.json()
        alert(data.errors ? data.errors.join(", ") : "Error creating value")
      }
    } catch (error) {
      alert("Error creating value")
    } finally {
      btn.disabled = false
    }
  }
}
