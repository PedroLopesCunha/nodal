import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "message"]
  static values = { refreshUrl: String, pendingText: String, successText: String, errorText: String, refreshErrorText: String }

  connect() {
    this.active = true
  }

  disconnect() {
    this.active = false
    clearTimeout(this.timer)
    this.request?.abort()
  }

  async start(event) {
    event.preventDefault()
    if (this.busy) return
    this.busy = true
    this.originalLabel = this.buttonTarget.innerHTML
    this.buttonTarget.disabled = true
    this.buttonTarget.textContent = this.pendingTextValue
    this.showMessage(this.pendingTextValue, "info")
    this.request = new AbortController()

    try {
      const response = await fetch(event.currentTarget.action, {
        method: "POST",
        body: new FormData(event.currentTarget),
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content },
        signal: this.request.signal
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || this.errorTextValue)
      this.statusUrl = data.status_url
      await this.poll()
    } catch (error) {
      if (this.active) this.finish(error.message || this.errorTextValue, "danger")
    }
  }

  async poll() {
    if (!this.active) return
    try {
      const response = await fetch(this.statusUrl, { headers: { Accept: "application/json" }, signal: this.request.signal })
      if (!response.ok) throw new Error(this.errorTextValue)
      const data = await response.json()
      if (!this.active) return
      if (data.status === "completed") {
        await this.refreshProduct()
      } else if (data.status === "failed" || data.status === "cancelled") {
        this.finish(data.error_message || this.errorTextValue, "danger")
      } else {
        this.timer = setTimeout(() => this.poll(), 1000)
      }
    } catch (error) {
      if (!this.active) return
      // Keep the button locked after a temporary polling failure: the ERP
      // job may still be running, so another submission could duplicate it.
      this.showMessage(this.pendingTextValue, "info")
      this.timer = setTimeout(() => this.poll(), 3000)
    }
  }

  async refreshProduct() {
    try {
      const response = await fetch(this.refreshUrlValue, { headers: { Accept: "text/html" }, signal: this.request.signal })
      if (!response.ok) throw new Error("refresh failed")
      const html = new DOMParser().parseFromString(await response.text(), "text/html")
      const updated = html.getElementById("product-details")
      if (!updated) throw new Error("missing product")
      if (!this.active) return
      const message = updated.querySelector('[data-product-erp-sync-target="message"]')
      message.textContent = this.successTextValue
      message.className = "alert alert-success"
      this.element.replaceWith(updated)
    } catch {
      if (this.active) this.finish(this.refreshErrorTextValue, "warning")
    }
  }

  finish(message, kind) {
    this.busy = false
    this.buttonTarget.disabled = false
    this.buttonTarget.innerHTML = this.originalLabel
    this.showMessage(message, kind)
  }

  showMessage(message, kind) {
    this.messageTarget.textContent = message
    this.messageTarget.className = `alert alert-${kind}`
  }
}
