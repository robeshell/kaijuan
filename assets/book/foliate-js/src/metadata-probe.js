import { EPUB } from './epub.js'
import {
  configure,
  ZipReader,
  BlobReader,
  TextWriter,
  BlobWriter,
} from './vendor/zip.js'

const callFlutter = (name, data) =>
  window.flutter_inappwebview.callHandler(name, data)

const blobToDataURL = blob => new Promise((resolve, reject) => {
  if (!blob) return resolve(null)
  const reader = new FileReader()
  reader.onerror = () => reject(reader.error)
  reader.onloadend = () => resolve(reader.result)
  reader.readAsDataURL(blob)
})

const makeZipLoader = async file => {
  configure({ useWebWorkers: false })
  const reader = new ZipReader(new BlobReader(file))
  const entries = await reader.getEntries()
  const map = new Map(entries.map(entry => [entry.filename, entry]))
  const load = fn => (name, ...args) =>
    map.has(name) ? fn(map.get(name), ...args) : null
  return {
    reader,
    loader: {
      entries,
      loadText: load(entry => entry.getData(new TextWriter())),
      loadBlob: load((entry, type) => entry.getData(new BlobWriter(type))),
      getSize: name => map.get(name)?.uncompressedSize ?? 0,
    },
  }
}

const sampleSpineText = async (book, maxSections = 12) => {
  const sections = book.sections || []
  const sampleCount = Math.min(sections.length, maxSections)
  if (!sampleCount) return {
    sampledSections: 0,
    sampledImageOnlySections: 0,
    totalTextLength: 0,
  }
  const indices = new Set()
  for (let i = 0; i < sampleCount; i++) {
    indices.add(sampleCount === 1
      ? 0
      : Math.round(i * (sections.length - 1) / (sampleCount - 1)))
  }
  let totalTextLength = 0
  let sampledImageOnlySections = 0
  for (const index of indices) {
    const section = sections[index]
    try {
      const directImage = /\.(avif|bmp|gif|jpe?g|png|svg|webp)(?:$|[?#])/i
        .test(String(section.id || ''))
      if (directImage) {
        sampledImageOnlySections++
        continue
      }
      const doc = await section.createDocument()
      const textLength = (doc?.body?.textContent || doc?.textContent || '').trim().length
      const containsImage = Boolean(doc?.querySelector?.(
        'img, svg, image, object[type^="image/"], input[type="image"]',
      ))
      totalTextLength += textLength
      if (containsImage && textLength <= 80) sampledImageOnlySections++
    } catch (error) {
      console.warn('Failed to sample EPUB section', index, error)
    } finally {
      section.unload?.()
    }
  }
  return {
    sampledSections: indices.size,
    sampledImageOnlySections,
    totalTextLength,
  }
}

const main = async () => {
  let zipReader
  try {
    const params = new URLSearchParams(window.location.search)
    const url = JSON.parse(params.get('url'))
    console.log('FoliateMetadataProbe fetch-start')
    const response = await fetch(url)
    if (!response.ok) throw new Error(`EPUB fetch failed: ${response.status}`)
    const blob = await response.blob()
    console.log('FoliateMetadataProbe fetch-ready', blob.size)

    const zip = await makeZipLoader(blob)
    zipReader = zip.reader
    const book = await new EPUB(zip.loader).init()
    console.log('FoliateMetadataProbe package-ready', book.sections?.length || 0)

    const [cover, sample] = await Promise.all([
      book.getCover().then(blobToDataURL).catch(error => {
        console.warn('Failed to read EPUB cover', error)
        return null
      }),
      sampleSpineText(book),
    ])
    await zipReader.close()
    zipReader = null
    await callFlutter('onMetadata', {
      ...book.metadata,
      cover,
      sectionCount: (book.sections || []).length,
      ...sample,
    })
  } catch (error) {
    console.error('FoliateMetadataProbe failed', error)
    await callFlutter('onProbeError', String(error?.message || error))
  } finally {
    await zipReader?.close()
  }
}

main()
