const visionUrl = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.21"
const modelUrl = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"

let reactLibraries

function loadScript(url) {
  return new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = url
    script.onload = resolve
    script.onerror = () => {
      script.remove()
      reject(new Error("Não foi possível carregar " + url))
    }
    document.head.appendChild(script)
  })
}

async function loadReactLibraries(reactUrl, reactDomUrl) {
  if (!window.React) await loadScript(reactUrl)
  if (!window.ReactDOM) await loadScript(reactDomUrl)
}

async function requestCamera(facing = "user") {
  try {
    return { stream: await navigator.mediaDevices.getUserMedia({
      video: { facingMode: facing === "environment" ? { exact: facing } : { ideal: facing }, width: { ideal: 640 } }, audio: false
    }) }
  } catch (error) {
    return { error }
  }
}

function releaseCameraRequest(request) {
  request?.then(({ stream }) => stream?.getTracks().forEach(track => track.stop()))
}

class VirtualTryOn {
  constructor(element) {
    this.dialogTarget = element.querySelector("dialog")
    this.chooserTarget = element.querySelector("[data-try-on-chooser]")
    this.loadingTarget = element.querySelector("[data-try-on-loading]")
    this.mountTarget = element.querySelector("[data-try-on-mount]")
    this.settings = element.dataset
    this.dialogTarget.addEventListener("close", () => this.unmount())
  }

  open(event) {
    if (typeof this.dialogTarget.showModal !== "function") return

    event.preventDefault()
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  useCamera() {
    if (this.opening) return

    const initialCameraRequest = navigator.mediaDevices?.getUserMedia ? requestCamera() : null
    this.cameraRequest = initialCameraRequest
    this.load({ initialCamera: true, initialCameraRequest })
  }

  usePhoto(input) {
    const file = input.files[0]
    input.value = ""
    if (file) this.load({ initialFile: file })
  }

  async load(selection) {
    if (this.opening || !this.dialogTarget.open) return

    const opening = Symbol()
    this.opening = opening
    this.chooserTarget.hidden = true
    this.loadingTarget.textContent = "A carregar o provador…"

    try {
      reactLibraries ||= loadReactLibraries(this.settings.reactUrl, this.settings.reactDomUrl).catch(error => {
        reactLibraries = null
        throw error
      })
      await reactLibraries
      if (this.opening !== opening || !this.dialogTarget.open) return

      this.loadingTarget.textContent = ""
      const { React, ReactDOM } = window
      this.root = ReactDOM.createRoot(this.mountTarget)
      this.root.render(React.createElement(TryOn, {
        React, ...selection, onCameraRequestTaken: () => { this.cameraRequest = null },
        imageUrl: this.settings.imageUrl, heightMm: Number(this.settings.heightMm),
        anchorX: Number(this.settings.anchorX), anchorY: Number(this.settings.anchorY)
      }))
    } catch (error) {
      if (this.opening === opening) {
        this.opening = null
        releaseCameraRequest(this.cameraRequest)
        this.cameraRequest = null
        this.chooserTarget.hidden = false
        this.loadingTarget.textContent = "Não foi possível carregar o provador. Tenta novamente."
      }
      console.error(error)
    }
  }

  close() {
    this.dialogTarget.close()
    this.unmount()
  }

  unmount() {
    if (this.dialogTarget.open) return

    this.opening = null
    releaseCameraRequest(this.cameraRequest)
    this.cameraRequest = null
    this.root?.unmount()
    this.root = null
    this.chooserTarget.hidden = false
    this.loadingTarget.textContent = ""
  }

}

const instances = new WeakMap()

function instanceFor(control) {
  const element = control.closest("[data-virtual-try-on]")
  if (!element) return null

  if (!instances.has(element)) instances.set(element, new VirtualTryOn(element))
  return instances.get(element)
}

document.addEventListener("click", event => {
  const opener = event.target.closest("[data-try-on-open]")
  if (opener) instanceFor(opener)?.open(event)

  const camera = event.target.closest("[data-try-on-camera]")
  if (camera) instanceFor(camera)?.useCamera()
})

document.addEventListener("change", event => {
  if (event.target.matches("[data-try-on-photo]")) instanceFor(event.target)?.usePhoto(event.target)
})

function closeOpenTryOns() {
  document.querySelectorAll("[data-virtual-try-on]").forEach(element => instances.get(element)?.close())
}

document.addEventListener("turbo:before-cache", closeOpenTryOns)
document.addEventListener("turbo:before-render", closeOpenTryOns)
window.addEventListener("pagehide", closeOpenTryOns)

function TryOn({ React, imageUrl, heightMm, anchorX, anchorY, initialCamera = false, initialCameraRequest, onCameraRequestTaken, initialFile }) {
  const { createElement: h, useEffect, useLayoutEffect, useRef, useState } = React
  const video = useRef(null)
  const photoInput = useRef(null)
  const photoRequest = useRef(0)
  const pendingFile = useRef(initialFile)
  const cameraRequest = useRef(initialCameraRequest)
  const canvas = useRef(null)
  const photoOverlay = useRef(null)
  const photoViewport = useRef(null)
  const photoPointers = useRef(new Map())
  const pendingScroll = useRef(null)
  const image = useRef(null)
  const productImage = useRef(null)
  const offsets = useRef({})
  const positions = useRef([])
  const drag = useRef(null)
  const [message, setMessage] = useState(initialCamera ? "A pedir acesso à câmara…" : "A preparar a fotografia…")
  const [imageError, setImageError] = useState("")
  const [photoReady, setPhotoReady] = useState(false)
  const [photoLoading, setPhotoLoading] = useState(Boolean(initialFile))
  const [cameraActive, setCameraActive] = useState(initialCamera)
  const [cameraReady, setCameraReady] = useState(false)
  const [cameraFacing, setCameraFacing] = useState("user")
  const [mirrored, setMirrored] = useState(true)
  const [cameraNotice, setCameraNotice] = useState("")
  const [snapshot, setSnapshot] = useState(null)
  const [zoom, setZoom] = useState(1)
  const [resumeError, setResumeError] = useState(false)

  useEffect(() => {
    if (!cameraActive) return

    const camera = video.current
    const overlay = canvas.current
    const context = overlay.getContext("2d")
    let active = true
    let stream
    let faceLandmarker
    let frame
    let previousTime = -1
    let landmarks
    let mirrorVideo = cameraFacing === "user"

    function release() {
      active = false
      cancelAnimationFrame(frame)
      stream?.getTracks().forEach(track => track.stop())
      camera.srcObject = null
      faceLandmarker?.close()
      faceLandmarker = null
      context.clearRect(0, 0, overlay.width, overlay.height)
    }

    function render(now) {
      if (camera.readyState >= 2 && camera.currentTime !== previousTime) {
        previousTime = camera.currentTime
        try {
          landmarks = faceLandmarker.detectForVideo(camera, now).faceLandmarks[0]
        } catch (error) {
          release()
          setCameraReady(false)
          setCameraActive(false)
          setMessage("O seguimento facial foi interrompido. Podes escolher uma fotografia.")
          console.error(error)
          return
        }

        if (overlay.width !== camera.videoWidth) overlay.width = camera.videoWidth
        if (overlay.height !== camera.videoHeight) overlay.height = camera.videoHeight
        context.clearRect(0, 0, overlay.width, overlay.height)

        const photo = image.current
        positions.current = landmarks && photo
          ? drawEarrings(context, landmarks, photo, heightMm, anchorX, anchorY, offsets.current, mirrorVideo)
          : []
      }
      frame = requestAnimationFrame(render)
    }

    async function start() {
      if (!navigator.mediaDevices?.getUserMedia) {
        setCameraActive(false)
        setMessage("A câmara não está disponível. Podes escolher uma fotografia.")
        return
      }

      try {
        const request = cameraRequest.current || requestCamera(cameraFacing)
        cameraRequest.current = null
        onCameraRequestTaken()
        const { stream: requestedStream, error } = await request
        if (error) throw error
        if (!active) {
          requestedStream.getTracks().forEach(track => track.stop())
          return
        }

        stream = requestedStream
        const actualFacing = stream.getVideoTracks()[0]?.getSettings().facingMode || cameraFacing
        mirrorVideo = actualFacing === "user"
        setMirrored(mirrorVideo)
        camera.srcObject = stream
        await camera.play()
        if (!active) return

        setMessage("A carregar o seguimento facial…")
        const detector = await createFaceLandmarker("VIDEO")
        if (!active) {
          detector.close()
          return
        }

        faceLandmarker = detector
        setCameraReady(true)
        setMessage("Se o brinco estiver descentrado, arrasta-o até ao lóbulo.")
        frame = requestAnimationFrame(render)
      } catch (error) {
        if (!active) return

        release()
        if (!stream && cameraFacing === "environment") {
          setCameraNotice("A câmara traseira não está disponível. A retomar a câmara frontal.")
          setCameraFacing("user")
          return
        }

        setCameraActive(false)
        setMessage(error.name === "NotAllowedError"
          ? "O acesso à câmara foi recusado. Podes escolher uma fotografia."
          : "Não foi possível iniciar a câmara. Podes escolher uma fotografia.")
        console.error(error)
      }
    }

    start()
    return release
  }, [cameraActive, cameraFacing, heightMm, anchorX, anchorY])

  useEffect(() => {
    let active = true
    const photo = new Image()
    photo.src = imageUrl
    productImage.current = photo.decode().then(() => {
      if (active) {
        image.current = photo
        setPhotoReady(true)
        return photo
      }
      return null
    }).catch(() => {
      if (active) {
        setPhotoLoading(false)
        setMessage("Podes tentar novamente fechando e voltando a abrir o provador.")
        setImageError("Não foi possível carregar a imagem do brinco.")
      }
      return null
    })
    return () => { active = false }
  }, [imageUrl])

  useEffect(() => {
    if (snapshot) paintPhotoEarrings(photoOverlay.current, image.current, snapshot.earrings)
  }, [snapshot])

  useLayoutEffect(() => {
    const scroll = pendingScroll.current
    if (!scroll || !photoViewport.current) return

    photoViewport.current.scrollTo(scroll.x, scroll.y)
    pendingScroll.current = null
  }, [zoom])

  function zoomPhoto(nextZoom, previous, current = previous) {
    const viewport = photoViewport.current
    const bounds = viewport.getBoundingClientRect()
    const scale = nextZoom / zoom
    const x = (viewport.scrollLeft + previous.x - bounds.left) * scale - (current.x - bounds.left)
    const y = (viewport.scrollTop + previous.y - bounds.top) * scale - (current.y - bounds.top)
    if (nextZoom === zoom) {
      viewport.scrollTo(x, y)
    } else {
      pendingScroll.current = { x, y }
      setZoom(nextZoom)
    }
  }

  function toggleZoom() {
    const bounds = photoViewport.current.getBoundingClientRect()
    zoomPhoto(zoom > 1 ? 1 : 2, { x: bounds.left + bounds.width / 2, y: bounds.top + bounds.height / 2 })
  }

  function startPhotoGesture(event) {
    const pointers = photoPointers.current
    if (event.button !== 0 || pointers.size >= 2) return

    pointers.set(event.pointerId, { x: event.clientX, y: event.clientY })
    event.currentTarget.setPointerCapture(event.pointerId)
    if (pointers.size === 1) startDrag(event)
    else drag.current = null
  }

  function movePhotoGesture(event) {
    const pointers = photoPointers.current
    const previous = pointers.get(event.pointerId)
    if (!previous) return

    const current = { x: event.clientX, y: event.clientY }
    pointers.set(event.pointerId, current)
    if (pointers.size === 2) {
      const other = Array.from(pointers.entries()).find(([id]) => id !== event.pointerId)[1]
      const previousDistance = Math.hypot(previous.x - other.x, previous.y - other.y)
      if (previousDistance === 0) return

      const distance = Math.hypot(current.x - other.x, current.y - other.y)
      const midpoint = point => ({ x: (point.x + other.x) / 2, y: (point.y + other.y) / 2 })
      zoomPhoto(Math.max(1, Math.min(4, zoom * distance / previousDistance)), midpoint(previous), midpoint(current))
    } else if (drag.current) {
      moveDrag(event)
    } else {
      photoViewport.current.scrollBy(previous.x - current.x, previous.y - current.y)
    }
  }

  function endPhotoGesture(event) {
    photoPointers.current.delete(event.pointerId)
    endDrag(event)
  }

  function pointerPosition(event) {
    const overlay = snapshot ? photoOverlay.current : canvas.current
    const bounds = overlay.getBoundingClientRect()
    return {
      x: (event.clientX - bounds.left) * overlay.width / bounds.width,
      y: (event.clientY - bounds.top) * overlay.height / bounds.height,
      hitRadius: 28 * overlay.width / bounds.width
    }
  }

  function startDrag(event) {
    if (!event.isPrimary || event.button !== 0 || drag.current) return

    const pointer = pointerPosition(event)
    const nearest = (snapshot ? snapshot.earrings : positions.current)
      .map(position => ({ ...position, distance: Math.hypot(pointer.x - position.x, pointer.y - position.y) }))
      .sort((first, second) => first.distance - second.distance)[0]
    if (!nearest || nearest.distance > Math.max(pointer.hitRadius, nearest.hitRadius)) return

    drag.current = { id: event.pointerId, side: nearest.side, x: pointer.x - nearest.x, y: pointer.y - nearest.y }
    event.currentTarget.setPointerCapture(event.pointerId)
  }

  function moveDrag(event) {
    const current = drag.current
    if (current?.id !== event.pointerId) return

    const position = (snapshot ? snapshot.earrings : positions.current).find(position => position.side === current.side)
    if (!position) return

    const pointer = pointerPosition(event)
    const x = pointer.x - current.x
    const y = pointer.y - current.y
    if (snapshot) {
      snapshot.adjusted = true
      position.x = x
      position.y = y
      paintPhotoEarrings(photoOverlay.current, image.current, snapshot.earrings)
    } else {
      offsets.current[current.side] = {
        x: (x - position.baseX) / position.scale,
        y: (y - position.baseY) / position.scale
      }
    }
  }

  function endDrag(event) {
    if (drag.current?.id === event.pointerId) drag.current = null
  }

  useEffect(() => () => {
    photoRequest.current += 1
    releaseCameraRequest(cameraRequest.current)
  }, [])

  function resetPhoto() {
    photoPointers.current.clear()
    pendingScroll.current = null
    drag.current = null
    setZoom(1)
    setSnapshot(null)
  }

  function startCamera() {
    if (navigator.mediaDevices?.getUserMedia) cameraRequest.current = requestCamera(cameraFacing)
    photoRequest.current += 1
    setPhotoLoading(false)
    resetPhoto()
    setMessage("A pedir acesso à câmara…")
    setCameraActive(true)
  }

  useEffect(() => {
    if (!pendingFile.current) return

    const file = pendingFile.current
    pendingFile.current = null
    choosePhoto(file)
  }, [])

  function selectPhoto(event) {
    const file = event.currentTarget.files[0]
    event.currentTarget.value = ""
    if (file) choosePhoto(file)
  }

  async function choosePhoto(file) {
    if (!file) return

    const request = ++photoRequest.current
    setCameraActive(false)
    setCameraReady(false)
    setPhotoLoading(true)
    resetPhoto()
    setMessage("A preparar a fotografia…")

    const url = URL.createObjectURL(file)
    let detector
    try {
      const photo = new Image()
      await new Promise((resolve, reject) => {
        photo.onload = resolve
        photo.onerror = reject
        photo.src = url
      })
      if (request !== photoRequest.current) return

      const scale = Math.min(1, 1600 / Math.max(photo.naturalWidth, photo.naturalHeight))
      const frame = document.createElement("canvas")
      frame.width = Math.max(1, Math.round(photo.naturalWidth * scale))
      frame.height = Math.max(1, Math.round(photo.naturalHeight * scale))
      const context = frame.getContext("2d")
      context.drawImage(photo, 0, 0, frame.width, frame.height)
      const preview = {
        url: frame.toDataURL("image/jpeg", 0.92), width: frame.width, height: frame.height,
        earrings: [], uploaded: true, findingFit: true
      }
      setSnapshot(preview)
      setPhotoLoading(false)

      const productPhoto = await productImage.current
      if (request !== photoRequest.current) return
      if (!productPhoto) {
        setSnapshot({ ...preview, findingFit: false })
        return
      }

      const photoHeight = Math.min(frame.width, frame.height) * 0.08
      const photoWidth = photoHeight * productPhoto.naturalWidth / productPhoto.naturalHeight
      const manual = {
        ...preview, manualPlacement: true, earrings: [{
          side: 0, x: frame.width / 2, y: frame.height / 2, opacity: 1,
          photoWidth, photoHeight, xOffset: photoWidth * anchorX, yOffset: photoHeight * anchorY,
          hitRadius: Math.max(photoWidth, photoHeight) / 2
        }]
      }
      setSnapshot(manual)

      let earrings = []
      try {
        detector = await createFaceLandmarker("IMAGE")
        if (request !== photoRequest.current) return

        const landmarks = detector.detect(frame).faceLandmarks[0]
        if (landmarks) {
          earrings = drawEarrings(context, landmarks, productPhoto, heightMm, anchorX, anchorY, {}, false)
        }
      } catch (error) {
        console.error(error)
      }

      if (request !== photoRequest.current) return
      setSnapshot(current => ({
        ...current,
        findingFit: false,
        ...(earrings.length && !current.adjusted && !drag.current ? { earrings, manualPlacement: false } : {})
      }))
    } catch {
      if (request === photoRequest.current) {
        setMessage("Não foi possível abrir a fotografia. Experimenta outro ficheiro, como JPEG ou PNG.")
      }
    } finally {
      detector?.close()
      URL.revokeObjectURL(url)
      if (request === photoRequest.current) setPhotoLoading(false)
    }
  }

  function switchCamera() {
    setCameraReady(false)
    setCameraNotice("")
    drag.current = null
    offsets.current = {}
    positions.current = []
    const nextFacing = cameraFacing === "user" ? "environment" : "user"
    setMessage(nextFacing === "environment" ? "A abrir a câmara traseira…" : "A abrir a câmara frontal…")
    setCameraFacing(nextFacing)
  }

  function takePhoto() {
    const camera = video.current
    const overlay = canvas.current
    if (camera.readyState < 2 || overlay.width !== camera.videoWidth || overlay.height !== camera.videoHeight) return

    const frame = document.createElement("canvas")
    frame.width = overlay.width
    frame.height = overlay.height
    const context = frame.getContext("2d")

    // Match the live view and keep the earrings in a separate, movable layer.
    if (mirrored) {
      context.translate(frame.width, 0)
      context.scale(-1, 1)
    }
    context.drawImage(camera, 0, 0)

    camera.pause()
    drag.current = null
    setResumeError(false)
    setSnapshot({
      url: frame.toDataURL("image/png"),
      width: frame.width,
      height: frame.height,
      earrings: positions.current.map(position => ({ ...position }))
    })
  }

  async function returnToCamera() {
    try {
      await video.current.play()
      resetPhoto()
    } catch {
      setResumeError(true)
    }
  }

  return h("div", null,
    imageError && h("p", { role: "alert", className: "text-danger" }, imageError),
    h("input", { ref: photoInput, type: "file", accept: "image/*", hidden: true, onChange: selectPhoto }),
    h("p", { role: "status", className: "small mb-2" },
      snapshot?.findingFit ? "A procurar o encaixe. Podes ajustar o brinco assim que aparecer."
        : snapshot?.manualPlacement ? "Não foi possível encontrar o encaixe. Arrasta o brinco até ao lóbulo."
        : snapshot ? "Podes arrastar o brinco para afinar o encaixe." : message),
    !snapshot && cameraNotice && h("p", { role: "status", className: "small mb-2" }, cameraNotice),
    !snapshot && !photoLoading && !cameraActive && h("div", { className: "d-flex flex-wrap justify-content-center gap-2 mb-3" },
      h("button", { type: "button", className: "btn btn-primary", onClick: startCamera }, "Usar câmara"),
      h("button", { type: "button", className: "btn btn-outline-primary", disabled: !photoReady || photoLoading,
        onClick: () => photoInput.current.click() }, "Escolher fotografia")),
    h("div", { hidden: !cameraActive || Boolean(snapshot), className: "position-relative bg-dark mb-3", style: { touchAction: "none" },
      onPointerDown: startDrag, onPointerMove: moveDrag, onPointerUp: endDrag,
      onPointerCancel: endDrag, onLostPointerCapture: endDrag },
      h("video", { ref: video, muted: true, playsInline: true, className: "d-block w-100", style: { transform: mirrored ? "scaleX(-1)" : undefined } }),
      h("canvas", { ref: canvas, "aria-hidden": true, className: "position-absolute top-0 start-0 w-100 h-100 pe-none" }),
      h("button", { type: "button", className: "btn btn-light rounded-circle shadow position-absolute bottom-0 start-50 translate-middle-x mb-3",
        style: { width: "3rem", height: "3rem" }, disabled: !cameraReady, onClick: takePhoto,
        "aria-label": "Tirar fotografia", title: "Tirar fotografia" },
        h("i", { className: "fa-solid fa-camera", "aria-hidden": true }))),
    snapshot
      ? h(React.Fragment, null,
        resumeError && h("p", { role: "alert" }, "Não foi possível retomar a câmara. Fecha e volta a abrir o provador."),
        h("div", { ref: photoViewport, className: "overflow-auto mb-3",
          style: { maxHeight: "60vh", touchAction: "none", overscrollBehavior: "contain" }, tabIndex: 0,
          "aria-label": "Pré-visualização da fotografia" },
          h("div", { className: "position-relative", style: { width: `${zoom * 100}%` },
            onPointerDown: startPhotoGesture, onPointerMove: movePhotoGesture, onPointerUp: endPhotoGesture,
            onPointerCancel: endPhotoGesture, onLostPointerCapture: endPhotoGesture },
            h("img", { src: snapshot.url, alt: "Fotografia do provador virtual", draggable: false, className: "d-block w-100" }),
            h("canvas", { ref: photoOverlay, width: snapshot.width, height: snapshot.height, "aria-hidden": true,
              className: "position-absolute top-0 start-0 w-100 h-100",
              style: { cursor: "grab" } }))),
        h("div", { className: "d-flex justify-content-center gap-2", role: "group", "aria-label": "Opções da fotografia" },
          photoAction(h, zoom > 1 ? "magnifying-glass-minus" : "magnifying-glass-plus",
            zoom > 1 ? "Reduzir fotografia" : "Ampliar fotografia", toggleZoom, "btn-primary"),
          snapshot.uploaded && photoAction(h, "image", "Escolher outra fotografia", () => photoInput.current.click()),
          photoAction(h, "camera", snapshot.uploaded ? "Usar câmara" : "Voltar à câmara",
            snapshot.uploaded ? startCamera : returnToCamera)))
      : cameraActive && h("div", { className: "d-flex justify-content-center gap-2", role: "group", "aria-label": "Opções da câmara" },
        photoAction(h, "image", "Escolher fotografia", () => photoInput.current.click(), "btn-outline-secondary", !photoReady),
        photoAction(h, "camera-rotate", cameraFacing === "user" ? "Usar câmara traseira" : "Usar câmara frontal",
          switchCamera, "btn-outline-secondary", !cameraReady),
        photoAction(h, "rotate-left", "Repor posição", () => {
          drag.current = null
          offsets.current = {}
        }, "btn-outline-secondary", !cameraReady)))
}


function photoAction(h, icon, label, onClick, variant = "btn-outline-secondary", disabled = false) {
  return h("button", {
    type: "button", className: `btn ${variant} d-inline-flex align-items-center justify-content-center`,
    style: { width: "44px", height: "44px" },
    "aria-label": label, title: label, onClick, disabled
  }, h("i", { className: `fa-solid fa-${icon}`, "aria-hidden": true }))
}

async function createFaceLandmarker(runningMode) {
  const { FaceLandmarker, FilesetResolver } = await import(visionUrl + "/vision_bundle.mjs")
  const fileset = await FilesetResolver.forVisionTasks(visionUrl + "/wasm")
  return FaceLandmarker.createFromOptions(fileset, {
    baseOptions: { modelAssetPath: modelUrl },
    runningMode,
    numFaces: 1
  })
}

function drawEarrings(context, landmarks, photo, heightMm, anchorX, anchorY, offsets, mirrored = true) {
  if (!(heightMm > 0)) return []

  const { width, height } = context.canvas
  const point = index => ({
    x: (mirrored ? 1 - landmarks[index].x : landmarks[index].x) * width,
    y: landmarks[index].y * height,
    z: landmarks[index].z * width
  })
  const distance = (first, second) => Math.hypot(first.x - second.x, first.y - second.y, first.z - second.z)
  const firstEye = point(33)
  const secondEye = point(263)
  // Include depth so the estimated size does not shrink as the head turns.
  const scale = distance(firstEye, secondEye) / 90
  if (!(scale > 0)) return []

  const photoHeight = heightMm * scale
  const photoWidth = photoHeight * photo.naturalWidth / photo.naturalHeight
  const xOffset = photoWidth * anchorX
  const yOffset = photoHeight * anchorY
  const firstCheek = point(234)
  const secondCheek = point(454)
  const cheekDistance = distance(firstCheek, secondCheek)
  if (!(cheekDistance > 0)) return []

  const depthDifference = firstCheek.z - secondCheek.z

  const positions = []
  for (const [side, cheek, jaw, depth] of [
    [132, firstCheek, point(132), depthDifference],
    [361, secondCheek, point(361), -depthDifference]
  ]) {
    // MediaPipe tracks the face contour. Approximate the lobe just outside it.
    const oppositeCheek = cheek === firstCheek ? secondCheek : firstCheek
    const nearSide = Math.min(1, Math.max(0, -depth / cheekDistance) / 0.5)
    const lateralOffset = 0.025 + nearSide * 0.07
    const baseX = (cheek.x + jaw.x) / 2 + (cheek.x - oppositeCheek.x) * lateralOffset
    const baseY = (cheek.y + jaw.y) / 2 + (cheek.y - oppositeCheek.y) * lateralOffset
      + (jaw.y - cheek.y) * nearSide * 0.18
    // Positive depth means this side is farther from the camera.
    context.globalAlpha = Math.max(0, Math.min(1, (0.36 - depth / cheekDistance) / 0.16))
    if (context.globalAlpha === 0) continue

    const x = baseX + (offsets[side]?.x ?? 0) * scale
    const y = baseY + (offsets[side]?.y ?? 0) * scale
    context.drawImage(photo, x - xOffset, y - yOffset, photoWidth, photoHeight)
    positions.push({ side, x, y, baseX, baseY, scale, xOffset, yOffset, photoWidth, photoHeight, opacity: context.globalAlpha, hitRadius: Math.max(xOffset, photoWidth - xOffset, yOffset, photoHeight - yOffset) })
  }
  context.globalAlpha = 1
  return positions
}

function paintPhotoEarrings(overlay, photo, earrings) {
  const context = overlay.getContext("2d")
  context.clearRect(0, 0, overlay.width, overlay.height)

  for (const earring of earrings) {
    context.globalAlpha = earring.opacity
    context.drawImage(photo, earring.x - earring.xOffset, earring.y - earring.yOffset,
      earring.photoWidth, earring.photoHeight)
  }
  context.globalAlpha = 1
}
