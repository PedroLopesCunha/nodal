import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["zipInput", "imageInput", "zipDropZone", "zipFileName", "photoModeSection"]

  connect() {
    this.dragCounter = 0
  }

  zipDragover(event) {
    event.preventDefault()
    event.stopPropagation()
  }

  zipDragenter(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dragCounter++
    this.zipDropZoneTarget.classList.add("border-primary", "bg-light")
  }

  zipDragleave(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dragCounter--
    if (this.dragCounter === 0) {
      this.zipDropZoneTarget.classList.remove("border-primary", "bg-light")
    }
  }

  zipDrop(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dragCounter = 0
    this.zipDropZoneTarget.classList.remove("border-primary", "bg-light")

    const files = event.dataTransfer.files
    if (files.length === 0) return

    const file = files[0]
    if (file.name.toLowerCase().endsWith(".zip")) {
      this.zipInputTarget.files = files
      this.updateFileName(`<i class="fa-solid fa-file-zipper text-warning me-2"></i><strong>${file.name}</strong>`)
      this.photoModeSectionTarget.classList.remove("d-none")
    } else if (this.areImageFiles(files)) {
      this.imageInputTarget.files = files
      this.updateFileName(`<i class="fa-solid fa-images text-success me-2"></i><strong>${files.length} image(s) selected</strong>`)
      this.photoModeSectionTarget.classList.remove("d-none")
    }
  }

  zipSelected() {
    if (this.zipInputTarget.files.length > 0) {
      this.updateFileName(`<i class="fa-solid fa-file-zipper text-warning me-2"></i><strong>${this.zipInputTarget.files[0].name}</strong>`)
      this.photoModeSectionTarget.classList.remove("d-none")
    } else {
      this.checkIfPhotosSelected()
    }
  }

  imagesSelected() {
    if (this.imageInputTarget.files.length > 0) {
      this.updateFileName(`<i class="fa-solid fa-images text-success me-2"></i><strong>${this.imageInputTarget.files.length} image(s) selected</strong>`)
      this.photoModeSectionTarget.classList.remove("d-none")
    } else {
      this.checkIfPhotosSelected()
    }
  }

  checkIfPhotosSelected() {
    const hasZip = this.zipInputTarget.files.length > 0
    const hasImages = this.imageInputTarget.files.length > 0
    if (!hasZip && !hasImages) {
      this.photoModeSectionTarget.classList.add("d-none")
    }
  }

  areImageFiles(files) {
    const imageExts = [".jpg", ".jpeg", ".png", ".gif", ".webp"]
    return Array.from(files).every(f => imageExts.some(ext => f.name.toLowerCase().endsWith(ext)))
  }

  updateFileName(html) {
    if (this.hasZipFileNameTarget) {
      this.zipFileNameTarget.innerHTML = html
    }
  }
}
