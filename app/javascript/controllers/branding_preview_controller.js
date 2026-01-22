import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "primaryColorInput",
    "primaryColorPicker",
    "secondaryColorInput",
    "secondaryColorPicker",
    "logoFallback",
    "primaryButton",
    "outlineButton"
  ]

  connect() {
    this.updatePreview()
  }

  syncFromPicker(event) {
    const picker = event.target
    const inputId = picker.dataset.inputTarget
    const input = this.element.querySelector(`#${inputId}`)
    if (input) {
      input.value = picker.value.toUpperCase()
      this.updatePreview()
    }
  }

  syncFromInput(event) {
    const input = event.target
    const pickerId = input.dataset.pickerTarget
    const picker = this.element.querySelector(`#${pickerId}`)

    if (this.isValidHex(input.value)) {
      if (picker) {
        picker.value = input.value
      }
      this.updatePreview()
    }
  }

  updatePreview() {
    const primaryColor = this.getPrimaryColor()
    const secondaryColor = this.getSecondaryColor()
    const primaryHover = this.darkenColor(primaryColor, 15)
    const contrastColor = this.getContrastColor(primaryColor)

    // Update logo fallback
    if (this.hasLogoFallbackTarget) {
      this.logoFallbackTarget.style.backgroundColor = primaryColor
      this.logoFallbackTarget.style.color = contrastColor
    }

    // Update primary button
    if (this.hasPrimaryButtonTarget) {
      this.primaryButtonTarget.style.backgroundColor = primaryColor
      this.primaryButtonTarget.style.borderColor = primaryColor
      this.primaryButtonTarget.style.color = contrastColor
    }

    // Update outline button
    if (this.hasOutlineButtonTarget) {
      this.outlineButtonTarget.style.borderColor = primaryColor
      this.outlineButtonTarget.style.color = primaryColor
    }
  }

  getPrimaryColor() {
    if (this.hasPrimaryColorInputTarget) {
      const value = this.primaryColorInputTarget.value
      return this.isValidHex(value) ? value : '#008060'
    }
    return '#008060'
  }

  getSecondaryColor() {
    if (this.hasSecondaryColorInputTarget) {
      const value = this.secondaryColorInputTarget.value
      return this.isValidHex(value) ? value : '#004c3f'
    }
    return '#004c3f'
  }

  isValidHex(color) {
    return /^#[0-9A-Fa-f]{6}$/.test(color)
  }

  darkenColor(hex, percent) {
    const num = parseInt(hex.slice(1), 16)
    const amt = Math.round(2.55 * percent)
    const R = Math.max((num >> 16) - amt, 0)
    const G = Math.max((num >> 8 & 0x00FF) - amt, 0)
    const B = Math.max((num & 0x0000FF) - amt, 0)
    return '#' + (0x1000000 + R * 0x10000 + G * 0x100 + B).toString(16).slice(1).toUpperCase()
  }

  getContrastColor(hex) {
    const num = parseInt(hex.slice(1), 16)
    const r = (num >> 16) & 255
    const g = (num >> 8) & 255
    const b = num & 255
    const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
    return luminance > 0.5 ? '#000000' : '#FFFFFF'
  }
}
