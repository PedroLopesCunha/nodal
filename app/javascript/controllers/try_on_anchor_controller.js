import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "image", "marker", "x", "y"]

  connect() {
    this.savedImage = this.imageTarget.getAttribute("src")
    this.renderMarker()
  }

  disconnect() {
    if (this.previewUrl) URL.revokeObjectURL(this.previewUrl)
  }

  preview(event) {
    if (this.previewUrl) URL.revokeObjectURL(this.previewUrl)
    const file = event.target.files[0]
    this.previewUrl = file ? URL.createObjectURL(file) : null
    const src = this.previewUrl || this.savedImage

    if (src) this.imageTarget.src = src
    else this.imageTarget.removeAttribute("src")
    this.previewTarget.style.display = src ? "" : "none"
  }

  place(event) {
    if (event.detail === 0) return

    const bounds = this.imageTarget.getBoundingClientRect()
    if (!bounds.width || !bounds.height) return

    this.setAnchor((event.clientX - bounds.left) / bounds.width, (event.clientY - bounds.top) / bounds.height)
  }

  move(event) {
    const steps = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }
    const direction = steps[event.key]
    if (!direction) return

    event.preventDefault()
    this.setAnchor(Number(this.xTarget.value) + direction[0] * 0.01,
      Number(this.yTarget.value) + direction[1] * 0.01)
  }

  setAnchor(x, y) {
    this.xTarget.value = Math.min(1, Math.max(0, x)).toFixed(4)
    this.yTarget.value = Math.min(1, Math.max(0, y)).toFixed(4)
    this.renderMarker()
  }

  renderMarker() {
    this.markerTarget.style.left = `${Number(this.xTarget.value) * 100}%`
    this.markerTarget.style.top = `${Number(this.yTarget.value) * 100}%`
  }
}
