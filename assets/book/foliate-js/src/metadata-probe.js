import {
  configure,
  ZipReader,
  BlobReader,
  TextWriter,
  BlobWriter,
} from './vendor/zip.js'

let zipReader

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

const isZip = async file => {
  const bytes = new Uint8Array(await file.slice(0, 4).arrayBuffer())
  return bytes[0] === 0x50 && bytes[1] === 0x4b
    && bytes[2] === 0x03 && bytes[3] === 0x04
}

const isPDF = async file => {
  const bytes = new Uint8Array(await file.slice(0, 5).arrayBuffer())
  return bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44
    && bytes[3] === 0x46 && bytes[4] === 0x2d
}

const isFB2 = file => file.name.toLowerCase().endsWith('.fb2')
const isFBZ = file => {
  const name = file.name.toLowerCase()
  return name.endsWith('.fbz') || name.endsWith('.fb2.zip')
}

const makeBook = async file => {
  if (await isPDF(file)) {
    const { makePDF } = await import('./pdf.js')
    return await makePDF(file)
  }

  if (await isZip(file)) {
    const zip = await makeZipLoader(file)
    zipReader = zip.reader
    if (isFBZ(file)) {
      const { makeFB2 } = await import('./fb2.js')
      const entry = zip.entries.find(entry =>
        entry.filename.toLowerCase().endsWith('.fb2'))
      const blob = await zip.loader.loadBlob(
        (entry ?? zip.entries[0]).filename,
      )
      return await makeFB2(blob)
    }
    const { EPUB } = await import('./epub.js')
    return await new EPUB(zip.loader).init()
  }

  if (isFB2(file)) {
    const { makeFB2 } = await import('./fb2.js')
    return await makeFB2(file)
  }

  const { isMOBI, MOBI } = await import('./mobi.js')
  if (await isMOBI(file)) {
    const fflate = await import('./vendor/fflate.js')
    return await new MOBI({ unzlib: fflate.unzlibSync }).open(file)
  }
  throw new Error('File type not supported')
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
  try {
    const params = new URLSearchParams(window.location.search)
    const url = JSON.parse(params.get('url'))
    console.log('FoliateMetadataProbe fetch-start')
    const response = await fetch(url)
    if (!response.ok) throw new Error(`Book fetch failed: ${response.status}`)
    const blob = await response.blob()
    const pathname = new URL(url, window.location.origin).pathname
    const rawName = pathname.split('/').pop() || 'book.bin'
    const name = decodeURIComponent(rawName)
    const file = new File([blob], name, { type: blob.type })
    console.log('FoliateMetadataProbe fetch-ready', name, blob.size)

    const book = await makeBook(file)
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
      ...(book.metadata || {}),
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
