import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["enabledToggle", "settingsPanel", "adapterSelect", "credentialsCard", "credentialsFields", "testButton", "testResult"]

  toggleEnabled() {
    if (this.enabledToggleTarget.checked) {
      this.settingsPanelTarget.classList.remove("d-none")
    } else {
      this.settingsPanelTarget.classList.add("d-none")
    }
  }

  changeAdapter() {
    const adapterType = this.adapterSelectTarget.value
    if (adapterType) {
      this.credentialsCardTarget.classList.remove("d-none")
    } else {
      this.credentialsCardTarget.classList.add("d-none")
    }
  }

  async testConnection(event) {
    event.preventDefault()

    const button = this.testButtonTarget
    const result = this.testResultTarget

    button.disabled = true
    button.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Testing...'
    result.innerHTML = ''

    try {
      const response = await fetch(this.testConnectionUrl, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({})
      })

      const data = await response.json()

      if (data.success) {
        result.innerHTML = '<span class="text-success"><i class="fa-solid fa-check-circle"></i> Connection successful!</span>'
      } else {
        result.innerHTML = `<span class="text-danger"><i class="fa-solid fa-times-circle"></i> ${data.error || 'Connection failed'}</span>`
      }
    } catch (error) {
      result.innerHTML = '<span class="text-danger"><i class="fa-solid fa-times-circle"></i> Connection test failed</span>'
    } finally {
      button.disabled = false
      button.innerHTML = '<i class="fa-solid fa-wifi"></i> Test Connection'
    }
  }

  get testConnectionUrl() {
    const path = window.location.pathname
    return path.replace(/\/edit$/, '/test_connection')
  }
}
