import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "content", "status"]

  disconnect() {
    this.abortController?.abort()
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  async open(event) {
    this.trigger = event.currentTarget
    this.dialogTarget.showModal()
    this.contentTarget.textContent = this.element.dataset.loading
    this.abortController?.abort()
    this.abortController = new AbortController()
    try {
      const response = await fetch(this.trigger.dataset.url, {
        headers: { Accept: "text/html" }, signal: this.abortController.signal
      })
      if (!response.ok || response.redirected) throw new Error()
      this.contentTarget.innerHTML = await response.text()
    } catch (error) {
      if (error.name !== "AbortError") this.contentTarget.textContent = this.element.dataset.error
    }
  }

  close() {
    this.abortController?.abort()
    this.dialogTarget.close()
    this.contentTarget.replaceChildren()
    this.trigger?.focus()
  }

  backdrop(event) {
    if (event.target !== this.dialogTarget) return
    const bounds = this.dialogTarget.getBoundingClientRect()
    if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) this.close()
  }

  async submit(event) {
    event.preventDefault()
    const form = event.target
    const button = event.submitter
    if (button?.disabled) return
    if (button) button.disabled = true
    this.statusTarget.textContent = ""
    try {
      const response = await fetch(form.action, {
        method: "POST", body: new FormData(form),
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content }
      })
      if (response.redirected) throw new Error()
      const result = await response.json()
      if (result.cart_count != null) {
        document.querySelectorAll("[data-cart-count]").forEach(badge => {
          badge.textContent = result.cart_count
          badge.classList.toggle("d-none", result.cart_count === 0)
        })
      }
      // A bulk request can save some rows and reject others. Exclude saved
      // rows from a retry so their quantities cannot be added twice.
      for (const id of result.added_variant_ids || []) {
        const input = form.querySelector(`input[name="bulk_items[${id}]"]`)
        if (input) { input.value = 0; input.disabled = true; input.dispatchEvent(new Event("input", { bubbles: true })) }
      }
      if (!response.ok) {
        // Keep validation feedback visible inside an open dialog.
        const feedback = this.hasDialogTarget && this.dialogTarget.open ? this.contentTarget.querySelector('[role="alert"]') : null
        if (feedback) feedback.textContent = result.message
        else this.statusTarget.textContent = result.message
        return
      }
      if (this.hasDialogTarget && this.dialogTarget.open) this.close()
      this.statusTarget.textContent = ""
      document.querySelectorAll("[data-cart-count]").forEach(badge => {
        badge.textContent = result.cart_count
        badge.classList.toggle("d-none", result.cart_count === 0)
      })
    } catch {
      const feedback = this.hasDialogTarget && this.dialogTarget.open ? this.contentTarget.querySelector('[role="alert"]') : null
      if (feedback) feedback.textContent = this.element.dataset.error
      else this.statusTarget.textContent = this.element.dataset.error
    } finally {
      if (button) button.disabled = false
    }
  }
}
