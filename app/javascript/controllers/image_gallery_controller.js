import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mainImage", "thumbnail"]

  connect() {
    // Set first thumbnail as active
    if (this.thumbnailTargets.length > 0) {
      this.thumbnailTargets[0].classList.add("border-primary", "border-2")
    }
  }

  select(event) {
    const thumbnail = event.currentTarget
    const imageUrl = thumbnail.dataset.imageUrl

    // Update main image
    if (this.hasMainImageTarget) {
      this.mainImageTarget.src = imageUrl
    }

    // Update zoom modal image (found by ID since it's outside controller scope)
    const zoomImage = document.getElementById("zoomModalImage")
    if (zoomImage) {
      zoomImage.src = imageUrl
    }

    // Update active thumbnail styling
    this.thumbnailTargets.forEach(t => {
      t.classList.remove("border-primary", "border-2")
      t.classList.add("border")
    })
    thumbnail.classList.remove("border")
    thumbnail.classList.add("border-primary", "border-2")
  }
}
