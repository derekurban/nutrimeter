import { useEffect, useRef, useState } from 'react'

const FORMATS = ['ean_13', 'ean_8', 'upc_a', 'upc_e'] as const

interface Detector {
  detect(source: HTMLVideoElement): Promise<{ rawValue: string }[]>
}

interface NativeDetectorClass {
  new (options: { formats: string[] }): Detector
  getSupportedFormats(): Promise<string[]>
}

/**
 * Uses the browser's native BarcodeDetector where available (Chrome on Android), otherwise the
 * zxing-wasm ponyfill (iOS Safari, Firefox). The WASM file is bundled rather than fetched from a CDN.
 */
async function createDetector(): Promise<Detector> {
  const Native = (window as unknown as { BarcodeDetector?: NativeDetectorClass }).BarcodeDetector
  if (Native) {
    try {
      const supported = await Native.getSupportedFormats()
      const formats = FORMATS.filter((f) => supported.includes(f))
      if (formats.length) return new Native({ formats })
    } catch {
      /* fall through to the ponyfill */
    }
  }
  const [{ BarcodeDetector, prepareZXingModule }, { default: wasmUrl }] = await Promise.all([
    import('barcode-detector/ponyfill'),
    import('zxing-wasm/reader/zxing_reader.wasm?url'),
  ])
  prepareZXingModule({
    overrides: { locateFile: (path: string, prefix: string) => (path.endsWith('.wasm') ? wasmUrl : prefix + path) },
  })
  return new BarcodeDetector({ formats: [...FORMATS] })
}

function describeError(e: unknown): string {
  const name = e instanceof DOMException ? e.name : ''
  if (name === 'NotAllowedError') return 'Camera permission was denied. Allow camera access for this site and try again.'
  if (name === 'NotFoundError' || name === 'OverconstrainedError') return 'No camera was found on this device.'
  if (name === 'NotReadableError') return 'The camera is in use by another app.'
  return e instanceof Error ? e.message : 'Could not start the camera.'
}

interface Props {
  onDetected: (code: string) => void
  onClose: () => void
}

export function BarcodeScanner({ onDetected, onClose }: Props) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const onDetectedRef = useRef(onDetected)
  const [status, setStatus] = useState<'starting' | 'scanning' | 'error'>('starting')
  const [error, setError] = useState<string | null>(null)
  const [manual, setManual] = useState('')

  useEffect(() => {
    onDetectedRef.current = onDetected
  })

  // Capture-phase so Escape closes only the scanner, not the dialog underneath.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return
      e.stopImmediatePropagation()
      onClose()
    }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  }, [onClose])

  useEffect(() => {
    let cancelled = false
    let stream: MediaStream | null = null
    let timer: number | undefined

    const start = async () => {
      if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
        throw new Error('Camera access needs a secure (https://) connection. Open the app through its HTTPS address.')
      }
      const [detector, s] = await Promise.all([
        createDetector(),
        navigator.mediaDevices.getUserMedia({
          audio: false,
          video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } },
        }),
      ])
      stream = s
      const video = videoRef.current
      if (cancelled || !video) return
      video.srcObject = s
      await video.play()
      if (cancelled) return
      setStatus('scanning')

      const tick = async () => {
        if (cancelled) return
        try {
          if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
            const hit = (await detector.detect(video)).find((c) => /^\d{8,14}$/.test(c.rawValue))
            if (hit && !cancelled) {
              navigator.vibrate?.(60)
              onDetectedRef.current(hit.rawValue)
              return
            }
          }
        } catch {
          /* transient decode errors: keep scanning */
        }
        timer = window.setTimeout(tick, 120)
      }
      tick()
    }

    start().catch((e) => {
      if (cancelled) return
      setStatus('error')
      setError(describeError(e))
    })

    return () => {
      cancelled = true
      window.clearTimeout(timer)
      // Also covers a stream that resolved after unmount.
      stream?.getTracks().forEach((t) => t.stop())
    }
  }, [])

  const submitManual = () => {
    const code = manual.replace(/\D/g, '')
    if (code.length >= 8) onDetected(code)
  }

  return (
    <div className="scanner" role="dialog" aria-modal="true" aria-label="Scan barcode">
      <video ref={videoRef} className="scanner-video" playsInline muted autoPlay />
      <div className="scanner-frame" aria-hidden="true" />
      <div className="scanner-top">
        <span>Scan a barcode</span>
        <button className="icon-btn" onClick={onClose} aria-label="Close scanner">
          ×
        </button>
      </div>
      <div className="scanner-bottom">
        {status === 'starting' && <p>Starting camera…</p>}
        {status === 'scanning' && <p>Line up the barcode inside the box.</p>}
        {status === 'error' && <p className="scanner-error">{error}</p>}
        <form
          className="scanner-manual"
          onSubmit={(e) => {
            e.preventDefault()
            submitManual()
          }}
        >
          <input inputMode="numeric" placeholder="…or type the barcode number" value={manual} onChange={(e) => setManual(e.target.value)} />
          <button className="btn btn-primary" type="submit" disabled={manual.replace(/\D/g, '').length < 8}>
            Look up
          </button>
        </form>
      </div>
    </div>
  )
}
