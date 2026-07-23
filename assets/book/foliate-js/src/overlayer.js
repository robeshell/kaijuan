const createSVGElement = tag =>
    document.createElementNS('http://www.w3.org/2000/svg', tag)

export class Overlayer {
    #svg = createSVGElement('svg')
    #map = new Map()
    #doc = null
    constructor(doc) {
        this.#doc = doc
        Object.assign(this.#svg.style, {
            position: 'absolute', top: '0', left: '0',
            width: '100%', height: '100%',
            pointerEvents: 'none',
        })
    }
    get element() {
        return this.#svg
    }
    get #zoom() {
        // Safari does not zoom the client rects, while Chrome, Edge and Firefox does
        if (/^((?!chrome|android).)*AppleWebKit/i.test(navigator.userAgent) && !window.chrome) {
            return window.getComputedStyle(this.#doc.body).zoom || 1.0
        }
        return 1.0
    }
    #splitRangeByParagraph(range) {
        const ancestor = range.commonAncestorContainer
        const paragraphs = Array.from(ancestor.querySelectorAll?.('p, h1, h2, h3, h4') || [])

        const splitRanges = []
        paragraphs.forEach((p) => {
            const pRange = document.createRange()
            if (range.intersectsNode(p)) {
                pRange.selectNodeContents(p)
                if (pRange.compareBoundaryPoints(Range.START_TO_START, range) < 0) {
                    pRange.setStart(range.startContainer, range.startOffset)
                }
                if (pRange.compareBoundaryPoints(Range.END_TO_END, range) > 0) {
                    pRange.setEnd(range.endContainer, range.endOffset)
                }
                splitRanges.push(pRange)
            }
        })
        return splitRanges.length === 0 ? [range] : splitRanges
    }
    add(key, range, draw, options) {
        if (this.#map.has(key)) this.remove(key)
        if (typeof range === 'function') range = range(this.#svg.getRootNode())
        const zoom = this.#zoom
        let rects = []
        this.#splitRangeByParagraph(range).forEach((pRange) => {
            const pRects = Array.from(pRange.getClientRects()).map(rect => ({
                left: rect.left * zoom,
                top: rect.top * zoom,
                right: rect.right * zoom,
                bottom: rect.bottom * zoom,
                width: rect.width * zoom,
                height: rect.height * zoom,
            }))
            rects = rects.concat(pRects)
        })
        const element = draw(rects, options)
        this.#svg.append(element)
        this.#map.set(key, { range, draw, options, element, rects })
    }
    remove(key) {
        if (!this.#map.has(key)) return
        this.#svg.removeChild(this.#map.get(key).element)
        this.#map.delete(key)
    }
    redraw() {
        for (const obj of this.#map.values()) {
            const { range, draw, options, element } = obj
            this.#svg.removeChild(element)
            const zoom = this.#zoom
            let rects = []
            this.#splitRangeByParagraph(range).forEach((pRange) => {
                const pRects = Array.from(pRange.getClientRects()).map(rect => ({
                    left: rect.left * zoom,
                    top: rect.top * zoom,
                    right: rect.right * zoom,
                    bottom: rect.bottom * zoom,
                    width: rect.width * zoom,
                    height: rect.height * zoom,
                }))
                rects = rects.concat(pRects)
            })
            const el = draw(rects, options)
            this.#svg.append(el)
            obj.element = el
            obj.rects = rects
        }
    }
    hitTest({ x, y }) {
        const arr = Array.from(this.#map.entries())
        // loop in reverse to hit more recently added items first
        for (let i = arr.length - 1; i >= 0; i--) {
            const [key, obj] = arr[i]
            for (const { left, top, right, bottom } of obj.rects)
                if (top <= y && left <= x && bottom > y && right > x)
                    return [key, obj.range]
        }
        return []
    }
    static underline(rects, options = {}) {
        const { color = 'red', width: strokeWidth = 2, padding = 0, writingMode } = options
        const g = createSVGElement('g')
        g.setAttribute('fill', color)
        if (writingMode === 'vertical-rl' || writingMode === 'vertical-lr')
            for (const { right, top, height } of rects) {
                const el = createSVGElement('rect')
                el.setAttribute('x', right - strokeWidth / 2 + padding)
                el.setAttribute('y', top)
                el.setAttribute('height', height)
                el.setAttribute('width', strokeWidth)
                g.append(el)
            }
        else for (const { left, bottom, width } of rects) {
            const el = createSVGElement('rect')
            el.setAttribute('x', left)
            el.setAttribute('y', bottom - strokeWidth / 2 + padding)
            el.setAttribute('height', strokeWidth)
            el.setAttribute('width', width)
            g.append(el)
        }
        return g
    }
    static strikethrough(rects, options = {}) {
        const { color = 'red', width: strokeWidth = 2, writingMode } = options
        const g = createSVGElement('g')
        g.setAttribute('fill', color)
        if (writingMode === 'vertical-rl' || writingMode === 'vertical-lr')
            for (const { right, left, top, height } of rects) {
                const el = createSVGElement('rect')
                el.setAttribute('x', (right + left) / 2)
                el.setAttribute('y', top)
                el.setAttribute('height', height)
                el.setAttribute('width', strokeWidth)
                g.append(el)
            }
        else for (const { left, top, bottom, width } of rects) {
            const el = createSVGElement('rect')
            el.setAttribute('x', left)
            el.setAttribute('y', (top + bottom) / 2)
            el.setAttribute('height', strokeWidth)
            el.setAttribute('width', width)
            g.append(el)
        }
        return g
    }
    // Wavy underline. Keep the path *inside* the client rect — drawing below
    // `bottom` gets clipped by paginator overflow and looks like "no line".
    static squiggly(rects, options = {}) {
        const { color = 'red', width: strokeWidth = 2, writingMode } = options
        const g = createSVGElement('g')
        g.setAttribute('fill', 'none')
        g.setAttribute('stroke', color)
        g.setAttribute('stroke-width', strokeWidth)
        g.setAttribute('stroke-linecap', 'round')
        g.setAttribute('stroke-linejoin', 'round')
        const amp = Math.max(2, strokeWidth)
        const period = Math.max(6, strokeWidth * 3)
        if (writingMode === 'vertical-rl' || writingMode === 'vertical-lr') {
            for (const { right, top, height, left } of rects) {
                const el = createSVGElement('path')
                const x = (right + left) / 2
                const n = Math.max(1, Math.ceil(height / period))
                const step = height / n
                let d = `M${x} ${top}`
                for (let i = 0; i < n; i++) {
                    const y1 = top + (i + 0.5) * step
                    const y2 = top + (i + 1) * step
                    const dir = i % 2 === 0 ? -amp : amp
                    d += ` Q${x + dir} ${y1} ${x} ${y2}`
                }
                el.setAttribute('d', d)
                g.append(el)
            }
        } else {
            for (const { left, bottom, width, top } of rects) {
                const el = createSVGElement('path')
                // Sit near the baseline, still within the glyph box.
                const y = Math.min(bottom - strokeWidth, top + (bottom - top) * 0.92)
                const n = Math.max(1, Math.ceil(width / period))
                const step = width / n
                let d = `M${left} ${y}`
                for (let i = 0; i < n; i++) {
                    const x1 = left + (i + 0.5) * step
                    const x2 = left + (i + 1) * step
                    const dir = i % 2 === 0 ? -amp : amp
                    d += ` Q${x1} ${y + dir} ${x2} ${y}`
                }
                el.setAttribute('d', d)
                g.append(el)
            }
        }
        return g
    }
    static highlight(rects, options = {}) {
        const { color = 'red', padding = 0 } = options
        const g = createSVGElement('g')
        g.setAttribute('fill', color)
        g.style.opacity = 'var(--overlayer-highlight-opacity, .3)'
        g.style.mixBlendMode = 'var(--overlayer-highlight-blend-mode, normal)'
        for (const { left, top, height, width } of rects) {
            const el = createSVGElement('rect')
            el.setAttribute('x', left - padding)
            el.setAttribute('y', top - padding)
            el.setAttribute('height', height + padding * 2)
            el.setAttribute('width', width + padding * 2)
            g.append(el)
        }
        return g
    }
    static outline(rects, options = {}) {
        const { color = 'red', width: strokeWidth = 3, padding = 0, radius = 3 } = options
        const g = createSVGElement('g')
        g.setAttribute('fill', 'none')
        g.setAttribute('stroke', color)
        g.setAttribute('stroke-width', strokeWidth)
        for (const { left, top, height, width } of rects) {
            const el = createSVGElement('rect')
            el.setAttribute('x', left - padding)
            el.setAttribute('y', top - padding)
            el.setAttribute('height', height + padding * 2)
            el.setAttribute('width', width + padding * 2)
            el.setAttribute('rx', radius)
            g.append(el)
        }
        return g
    }
    // make an exact copy of an image in the overlay
    // one can then apply filters to the entire element, without affecting them;
    // it's a bit silly and probably better to just invert images twice
    // (though the color will be off in that case if you do heu-rotate)
    static copyImage([rect], options = {}) {
        const { src } = options
        const image = createSVGElement('image')
        const { left, top, height, width } = rect
        image.setAttribute('href', src)
        image.setAttribute('x', left)
        image.setAttribute('y', top)
        image.setAttribute('height', height)
        image.setAttribute('width', width)
        return image
    }
}
