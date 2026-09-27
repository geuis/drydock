// Builds the app icon from the ship in EV Nova's own icon.
//
// The ship is cut out of the game's icon (the NOVA lettering and the tiled
// background are dropped), then drawn half as the real ship and half as
// blueprint line art, with a pencil at the seam drawing it in. That says
// "editor for this game" without borrowing the game's title.
//
// Usage (from the repository root):
//   swift Tools/AppIcon/MakeAppIcon.swift ["/path/to/EV Nova.app"]
//
// Writes Tools/AppIcon/AppIcon.icns and Tools/AppIcon/AppIcon.png.

import AppKit
import CoreGraphics

// MARK: - Pixel buffer

// Straight RGBA bytes with the first row at the top, so image coordinates
// match what you see in the source icon.
struct PixelBuffer {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.bytes = [UInt8](repeating: 0, count: width * height * 4)
    }

    init(image: CGImage, width: Int, height: Int) {
        self.init(width: width, height: height)

        let context: CGContext = PixelBuffer.makeContext(data: &bytes, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    static func makeContext(data: UnsafeMutableRawPointer, width: Int, height: Int) -> CGContext {
        return CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    func luminance(at index: Int) -> Double {
        let red: Double = Double(bytes[index * 4])
        let green: Double = Double(bytes[index * 4 + 1])
        let blue: Double = Double(bytes[index * 4 + 2])
        return red * 0.3 + green * 0.6 + blue * 0.1
    }

    func makeImage() -> CGImage {
        var copy: [UInt8] = bytes
        let context: CGContext = PixelBuffer.makeContext(data: &copy, width: width, height: height)
        return context.makeImage()!
    }
}

// MARK: - Source icon

func loadSourceIcon(appPath: String) -> CGImage {
    let icnsPath: String = appPath + "/Contents/Resources/Nova.icns"

    guard let image: NSImage = NSImage(contentsOfFile: icnsPath) else {
        fatalError("Could not read \(icnsPath)")
    }

    // Pick the largest representation; the game ships a 512 pixel version.
    let largest: NSImageRep? = image.representations.max { $0.pixelsWide < $1.pixelsWide }
    var rect: CGRect = CGRect(x: 0, y: 0, width: largest?.pixelsWide ?? 512, height: largest?.pixelsHigh ?? 512)

    guard let cgImage: CGImage = largest?.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        fatalError("Nova.icns has no usable image")
    }

    return cgImage
}

// MARK: - Ship cutout

// A loose hand-placed outline around the ship in the 512 pixel source icon
// (y down). Everything outside it is background. Without it, the tiled
// background's light bevels join up with the hull and survive the cutout.
let shipOutline: [CGPoint] = [
    CGPoint(x: 36, y: 472), CGPoint(x: 38, y: 410), CGPoint(x: 105, y: 295), CGPoint(x: 185, y: 172),
    CGPoint(x: 260, y: 138), CGPoint(x: 330, y: 116), CGPoint(x: 422, y: 128), CGPoint(x: 472, y: 180),
    CGPoint(x: 472, y: 262), CGPoint(x: 466, y: 325), CGPoint(x: 440, y: 340), CGPoint(x: 360, y: 365),
    CGPoint(x: 260, y: 418), CGPoint(x: 150, y: 464), CGPoint(x: 75, y: 488)
]

func isInsidePolygon(_ point: CGPoint, _ polygon: [CGPoint]) -> Bool {
    var inside: Bool = false
    var previous: CGPoint = polygon[polygon.count - 1]

    for current in polygon {
        let crosses: Bool = (current.y > point.y) != (previous.y > point.y)

        if crosses {
            let crossingX: CGFloat = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x

            if point.x < crossingX {
                inside.toggle()
            }
        }

        previous = current
    }

    return inside
}

// Marks every pixel within `radius` of a marked pixel.
func grow(_ mask: [Bool], width: Int, height: Int, radius: Int) -> [Bool] {
    var result: [Bool] = mask

    for row in 0..<height {
        for column in 0..<width where !mask[row * width + column] {
            search: for deltaRow in -radius...radius {
                for deltaColumn in -radius...radius where deltaRow * deltaRow + deltaColumn * deltaColumn <= radius * radius {
                    let otherRow: Int = row + deltaRow
                    let otherColumn: Int = column + deltaColumn

                    if otherRow < 0 || otherRow >= height || otherColumn < 0 || otherColumn >= width {
                        continue
                    }

                    if mask[otherRow * width + otherColumn] {
                        result[row * width + column] = true
                        break search
                    }
                }
            }
        }
    }

    return result
}

func neighbors(of index: Int, width: Int, height: Int) -> [Int] {
    let row: Int = index / width
    let column: Int = index % width
    var result: [Int] = []

    if row > 0 { result.append(index - width) }
    if row < height - 1 { result.append(index + width) }
    if column > 0 { result.append(index - 1) }
    if column < width - 1 { result.append(index + 1) }

    return result
}

// Returns a mask of the ship's pixels in the source icon.
func cutOutShip(_ source: PixelBuffer) -> [Bool] {
    let width: Int = source.width
    let height: Int = source.height
    let count: Int = width * height
    let scale: CGFloat = CGFloat(width) / 512

    // The hull is light grey; the background is dark tiles and red lines.
    var hull: [Bool] = (0..<count).map { index in
        let red: Int = Int(source.bytes[index * 4])
        let green: Int = Int(source.bytes[index * 4 + 1])
        let isRedLine: Bool = red > green + 30
        return source.luminance(at: index) >= 60 && !isRedLine
    }

    // Thin dark seams between hull panels would otherwise let the fill leak
    // into the ship's dark window panels, so close them before filling.
    let closeRadius: Int = 3
    hull = grow(hull, width: width, height: height, radius: closeRadius)

    var background: [Bool] = [Bool](repeating: false, count: count)
    var pending: [Int] = []

    for index in 0..<count {
        let point: CGPoint = CGPoint(x: CGFloat(index % width) / scale, y: CGFloat(index / width) / scale)

        if !isInsidePolygon(point, shipOutline) {
            background[index] = true
            pending.append(contentsOf: neighbors(of: index, width: width, height: height))
        }
    }

    while let index = pending.popLast() {
        if background[index] || hull[index] {
            continue
        }

        background[index] = true
        pending.append(contentsOf: neighbors(of: index, width: width, height: height))
    }

    // Undo the gap closing so the outline sits back on the real hull edge.
    let backgroundGrown: [Bool] = grow(background, width: width, height: height, radius: closeRadius)
    return backgroundGrown.map { !$0 }
}

// The source ship with a soft-edged alpha taken from the mask, drawn at
// `size` so later line tracing works at the output resolution.
func makeShipLayer(source: PixelBuffer, mask: [Bool], size: Int) -> PixelBuffer {
    var maskBuffer: PixelBuffer = PixelBuffer(width: source.width, height: source.height)

    for index in 0..<(source.width * source.height) where mask[index] {
        maskBuffer.bytes[index * 4 + 3] = 255
    }

    let colour: PixelBuffer = PixelBuffer(image: source.makeImage(), width: size, height: size)
    let alpha: PixelBuffer = PixelBuffer(image: maskBuffer.makeImage(), width: size, height: size)
    var result: PixelBuffer = PixelBuffer(width: size, height: size)

    for index in 0..<(size * size) {
        result.bytes[index * 4] = colour.bytes[index * 4]
        result.bytes[index * 4 + 1] = colour.bytes[index * 4 + 1]
        result.bytes[index * 4 + 2] = colour.bytes[index * 4 + 2]
        result.bytes[index * 4 + 3] = alpha.bytes[index * 4 + 3]
    }

    return result
}

// MARK: - Blueprint half

struct Colour {
    let red: Double
    let green: Double
    let blue: Double

    var cgColor: CGColor {
        return CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    func cgColor(alpha: Double) -> CGColor {
        return CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

let blueprintInk: Colour = Colour(red: 0.78, green: 0.93, blue: 1.0)
let blueprintDeep: Colour = Colour(red: 0.05, green: 0.20, blue: 0.42)
let blueprintShallow: Colour = Colour(red: 0.09, green: 0.34, blue: 0.62)
let seamGlow: Colour = Colour(red: 0.55, green: 0.90, blue: 1.0)

// Traces the ship's panel lines and outline as light ink, with a faint
// wash inside the hull, like a technical drawing.
func makeBlueprintLayer(ship: PixelBuffer) -> PixelBuffer {
    let width: Int = ship.width
    let height: Int = ship.height
    var result: PixelBuffer = PixelBuffer(width: width, height: height)

    func alpha(_ column: Int, _ row: Int) -> Double {
        let clampedColumn: Int = min(max(column, 0), width - 1)
        let clampedRow: Int = min(max(row, 0), height - 1)
        return Double(ship.bytes[(clampedRow * width + clampedColumn) * 4 + 3]) / 255
    }

    func shade(_ column: Int, _ row: Int) -> Double {
        let clampedColumn: Int = min(max(column, 0), width - 1)
        let clampedRow: Int = min(max(row, 0), height - 1)
        return ship.luminance(at: clampedRow * width + clampedColumn) / 255 * alpha(column, row)
    }

    for row in 0..<height {
        for column in 0..<width {
            // Sobel edges of the shading pick out panel seams and vents.
            let horizontal: Double =
                (shade(column + 1, row - 1) + 2 * shade(column + 1, row) + shade(column + 1, row + 1))
                - (shade(column - 1, row - 1) + 2 * shade(column - 1, row) + shade(column - 1, row + 1))
            let vertical: Double =
                (shade(column - 1, row + 1) + 2 * shade(column, row + 1) + shade(column + 1, row + 1))
                - (shade(column - 1, row - 1) + 2 * shade(column, row - 1) + shade(column + 1, row - 1))
            let edge: Double = min(1, max(0, (sqrt(horizontal * horizontal + vertical * vertical) - 0.35) * 1.6))

            let wash: Double = alpha(column, row) * 0.16
            let ink: Double = max(edge, wash)
            let index: Int = row * width + column

            result.bytes[index * 4] = UInt8(blueprintInk.red * 255)
            result.bytes[index * 4 + 1] = UInt8(blueprintInk.green * 255)
            result.bytes[index * 4 + 2] = UInt8(blueprintInk.blue * 255)
            result.bytes[index * 4 + 3] = UInt8(ink * 255)
        }
    }

    return result
}

// MARK: - Splitting the ship

// Where the ship turns from real to blueprint, in the 1024 layer (y down).
// The seam runs across the ship, square to its nose-to-engines line.
let shipNose: CGPoint = CGPoint(x: 110, y: 910)
let shipTail: CGPoint = CGPoint(x: 840, y: 300)
let seamFraction: CGFloat = 0.52

var seamPoint: CGPoint {
    return CGPoint(
        x: shipNose.x + (shipTail.x - shipNose.x) * seamFraction,
        y: shipNose.y + (shipTail.y - shipNose.y) * seamFraction
    )
}

// Signed distance along the ship's axis from the seam; positive toward the engines.
func distanceFromSeam(column: Int, row: Int) -> Double {
    let axisX: Double = Double(shipTail.x - shipNose.x)
    let axisY: Double = Double(shipTail.y - shipNose.y)
    let length: Double = sqrt(axisX * axisX + axisY * axisY)
    return ((Double(column) - Double(seamPoint.x)) * axisX + (Double(row) - Double(seamPoint.y)) * axisY) / length
}

func blend(_ over: UInt8, _ under: UInt8, _ amount: Double) -> UInt8 {
    return UInt8(Double(over) * amount + Double(under) * (1 - amount))
}

// Real ship toward the nose, blueprint toward the engines, and a bright
// line on the hull where the pencil is drawing.
func makeSplitShip(ship: PixelBuffer, blueprint: PixelBuffer) -> PixelBuffer {
    var result: PixelBuffer = PixelBuffer(width: ship.width, height: ship.height)
    let fadeWidth: Double = 10
    let glowWidth: Double = 5

    for row in 0..<ship.height {
        for column in 0..<ship.width {
            let index: Int = row * ship.width + column
            let distance: Double = distanceFromSeam(column: column, row: row)
            let realAmount: Double = min(1, max(0, 0.5 - distance / fadeWidth))

            for channel in 0..<4 {
                result.bytes[index * 4 + channel] = blend(ship.bytes[index * 4 + channel], blueprint.bytes[index * 4 + channel], realAmount)
            }

            let shipAlpha: Double = Double(ship.bytes[index * 4 + 3]) / 255
            let glow: Double = exp(-(distance * distance) / (2 * glowWidth * glowWidth)) * shipAlpha

            if glow > 0.01 {
                result.bytes[index * 4] = blend(UInt8(seamGlow.red * 255), result.bytes[index * 4], glow)
                result.bytes[index * 4 + 1] = blend(UInt8(seamGlow.green * 255), result.bytes[index * 4 + 1], glow)
                result.bytes[index * 4 + 2] = blend(UInt8(seamGlow.blue * 255), result.bytes[index * 4 + 2], glow)
                result.bytes[index * 4 + 3] = max(result.bytes[index * 4 + 3], UInt8(glow * 255))
            }
        }
    }

    return result
}

// MARK: - Drawing the icon

let canvasSize: CGFloat = 1024

// Apple's macOS icon grid: an 824 point rounded square centred on the canvas.
let tileRect: CGRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 185

func drawTile(in context: CGContext) {
    let tilePath: CGPath = CGPath(roundedRect: tileRect, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)

    // Drop shadow under the tile, as system icons have.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.45))
    context.addPath(tilePath)
    context.setFillColor(blueprintDeep.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    let gradient: CGGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [blueprintShallow.cgColor, blueprintDeep.cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: tileRect.minX, y: tileRect.maxY),
        end: CGPoint(x: tileRect.maxX, y: tileRect.minY),
        options: []
    )

    drawGrid(in: context)
    context.restoreGState()

    // A thin light rim keeps the tile edge crisp on dark docks.
    context.addPath(CGPath(roundedRect: tileRect.insetBy(dx: 1.5, dy: 1.5), cornerWidth: tileRadius - 1.5, cornerHeight: tileRadius - 1.5, transform: nil))
    context.setStrokeColor(blueprintInk.cgColor(alpha: 0.25))
    context.setLineWidth(3)
    context.strokePath()
}

func drawGrid(in context: CGContext) {
    let minorStep: CGFloat = 824 / 24
    let majorEvery: Int = 4

    for step in 0...24 {
        let offset: CGFloat = CGFloat(step) * minorStep
        let isMajor: Bool = step % majorEvery == 0

        context.setStrokeColor(blueprintInk.cgColor(alpha: isMajor ? 0.16 : 0.07))
        context.setLineWidth(isMajor ? 2.5 : 1.5)

        context.move(to: CGPoint(x: tileRect.minX + offset, y: tileRect.minY))
        context.addLine(to: CGPoint(x: tileRect.minX + offset, y: tileRect.maxY))
        context.move(to: CGPoint(x: tileRect.minX, y: tileRect.minY + offset))
        context.addLine(to: CGPoint(x: tileRect.maxX, y: tileRect.minY + offset))
        context.strokePath()
    }
}

// The ship layer is canvas sized, but the hull runs nearly edge to edge, so
// it is shrunk and moved to sit inside the tile with room for the pencil.
let shipScale: CGFloat = 0.8
let shipCentreInLayer: CGPoint = CGPoint(x: 508, y: 604)
let shipCentreOnCanvas: CGPoint = CGPoint(x: 500, y: 490)

// Maps a y-down ship layer point to the y-up canvas.
func canvasPoint(fromLayer point: CGPoint) -> CGPoint {
    let x: CGFloat = shipCentreOnCanvas.x + (point.x - shipCentreInLayer.x) * shipScale
    let yDown: CGFloat = shipCentreOnCanvas.y + (point.y - shipCentreInLayer.y) * shipScale
    return CGPoint(x: x, y: canvasSize - yDown)
}

func drawShip(_ ship: CGImage, in context: CGContext) {
    let topLeft: CGPoint = canvasPoint(fromLayer: CGPoint(x: 0, y: 0))
    let side: CGFloat = canvasSize * shipScale
    let destination: CGRect = CGRect(x: topLeft.x, y: topLeft.y - side, width: side, height: side)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: CGColor(gray: 0, alpha: 0.5))
    context.interpolationQuality = .high
    context.draw(ship, in: destination)
    context.restoreGState()
}

// A classic yellow pencil, drawn pointing along +x from the origin, then
// rotated into place so its tip touches the seam.
func drawPencil(in context: CGContext, tip: CGPoint, angle: CGFloat) {
    let length: CGFloat = 470
    let bodyWidth: CGFloat = 74
    let coneLength: CGFloat = 92
    let leadLength: CGFloat = 30
    let ferruleLength: CGFloat = 46
    let eraserLength: CGFloat = 50
    let half: CGFloat = bodyWidth / 2

    let bodyStart: CGFloat = coneLength
    let bodyEnd: CGFloat = length - ferruleLength - eraserLength
    let ferruleEnd: CGFloat = length - eraserLength

    context.saveGState()
    context.translateBy(x: tip.x, y: tip.y)
    context.rotate(by: angle)

    context.setShadow(offset: CGSize(width: 10, height: -16), blur: 26, color: CGColor(gray: 0, alpha: 0.5))
    context.beginTransparencyLayer(auxiliaryInfo: nil)

    // Wood cone.
    context.move(to: CGPoint(x: 0, y: 0))
    context.addLine(to: CGPoint(x: bodyStart, y: half))
    context.addLine(to: CGPoint(x: bodyStart, y: -half))
    context.closePath()
    context.setFillColor(CGColor(srgbRed: 0.93, green: 0.78, blue: 0.58, alpha: 1))
    context.fillPath()

    // Shaded lower facet of the cone.
    context.move(to: CGPoint(x: 0, y: 0))
    context.addLine(to: CGPoint(x: bodyStart, y: -half))
    context.addLine(to: CGPoint(x: bodyStart, y: -half / 3))
    context.closePath()
    context.setFillColor(CGColor(srgbRed: 0.80, green: 0.62, blue: 0.42, alpha: 1))
    context.fillPath()

    // Graphite point.
    let leadHalf: CGFloat = half * leadLength / coneLength
    context.move(to: CGPoint(x: 0, y: 0))
    context.addLine(to: CGPoint(x: leadLength, y: leadHalf))
    context.addLine(to: CGPoint(x: leadLength, y: -leadHalf))
    context.closePath()
    context.setFillColor(CGColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1))
    context.fillPath()

    // Painted body in three faces, lit from above.
    let faces: [(CGFloat, CGFloat, CGColor)] = [
        (half / 3, half, CGColor(srgbRed: 1.0, green: 0.84, blue: 0.30, alpha: 1)),
        (-half / 3, half / 3, CGColor(srgbRed: 0.98, green: 0.72, blue: 0.13, alpha: 1)),
        (-half, -half / 3, CGColor(srgbRed: 0.88, green: 0.56, blue: 0.08, alpha: 1))
    ]

    for (bottom, top, colour) in faces {
        context.setFillColor(colour)
        context.fill(CGRect(x: bodyStart, y: bottom, width: bodyEnd - bodyStart, height: top - bottom))
    }

    // Scalloped edge where the paint meets the sharpened wood.
    context.setFillColor(CGColor(srgbRed: 0.93, green: 0.78, blue: 0.58, alpha: 1))

    for scallop in 0..<3 {
        let centreY: CGFloat = -half + bodyWidth / 6 + CGFloat(scallop) * bodyWidth / 3
        context.addEllipse(in: CGRect(x: bodyStart - bodyWidth / 6, y: centreY - bodyWidth / 6, width: bodyWidth / 3, height: bodyWidth / 3))
    }

    context.fillPath()

    // Metal ferrule with a couple of crimp bands.
    let ferrule: CGGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            CGColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1),
            CGColor(srgbRed: 0.66, green: 0.69, blue: 0.74, alpha: 1),
            CGColor(srgbRed: 0.45, green: 0.48, blue: 0.53, alpha: 1)
        ] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.saveGState()
    context.clip(to: CGRect(x: bodyEnd, y: -half - 2, width: ferruleLength, height: bodyWidth + 4))
    context.drawLinearGradient(ferrule, start: CGPoint(x: 0, y: half + 2), end: CGPoint(x: 0, y: -half - 2), options: [])
    context.restoreGState()

    context.setStrokeColor(CGColor(srgbRed: 0.38, green: 0.40, blue: 0.45, alpha: 1))
    context.setLineWidth(3)

    for band in [bodyEnd + 12, bodyEnd + ferruleLength - 12] {
        context.move(to: CGPoint(x: band, y: -half - 2))
        context.addLine(to: CGPoint(x: band, y: half + 2))
    }

    context.strokePath()

    // Rounded eraser. EV Nova's red, to tie the pencil back to the game.
    let eraser: CGPath = CGPath(
        roundedRect: CGRect(x: ferruleEnd - 12, y: -half, width: eraserLength + 12, height: bodyWidth),
        cornerWidth: 18,
        cornerHeight: 18,
        transform: nil
    )
    context.saveGState()
    context.addPath(eraser)
    context.clip()
    context.clip(to: CGRect(x: ferruleEnd, y: -half, width: eraserLength, height: bodyWidth))
    let eraserGradient: CGGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            CGColor(srgbRed: 0.95, green: 0.42, blue: 0.40, alpha: 1),
            CGColor(srgbRed: 0.72, green: 0.14, blue: 0.14, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(eraserGradient, start: CGPoint(x: 0, y: half), end: CGPoint(x: 0, y: -half), options: [])
    context.restoreGState()

    context.endTransparencyLayer()
    context.restoreGState()
}

func renderIcon(shipLayer: CGImage) -> CGImage {
    let size: Int = Int(canvasSize)
    var buffer: PixelBuffer = PixelBuffer(width: size, height: size)
    let context: CGContext = PixelBuffer.makeContext(data: &buffer.bytes, width: size, height: size)

    drawTile(in: context)

    // Keep the ship and pencil inside the tile so nothing pokes past the corners.
    context.saveGState()
    context.addPath(CGPath(roundedRect: tileRect, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil))
    context.clip()
    drawShip(shipLayer, in: context)
    context.restoreGState()

    // Nudge the tip from the seam's middle toward the hull's lower edge so
    // it reads as drawing on the ship rather than hiding behind it.
    let tip: CGPoint = canvasPoint(fromLayer: CGPoint(x: seamPoint.x + 70, y: seamPoint.y + 85))
    drawPencil(in: context, tip: tip, angle: -.pi / 3.4)

    return context.makeImage()!
}

// MARK: - Output

func writePNG(_ image: CGImage, size: Int, to url: URL) {
    var buffer: PixelBuffer = PixelBuffer(width: size, height: size)
    let context: CGContext = PixelBuffer.makeContext(data: &buffer.bytes, width: size, height: size)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

    let rep: NSBitmapImageRep = NSBitmapImageRep(cgImage: context.makeImage()!)

    guard let data: Data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode \(url.path)")
    }

    try! data.write(to: url)
}

func writeIconSet(_ image: CGImage, to folder: URL) {
    try? FileManager.default.removeItem(at: folder)
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let entries: [(String, Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
    ]

    for (name, size) in entries {
        writePNG(image, size: size, to: folder.appendingPathComponent(name))
    }
}

func runIconutil(iconSet: URL, output: URL) {
    let process: Process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconSet.path, "-o", output.path]
    try! process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        fatalError("iconutil failed")
    }
}

let defaultGameApp: String = NSString(string: "~/Desktop/EV Nova/EV Nova.app").expandingTildeInPath
let gameAppPath: String = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultGameApp
let scriptFolder: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

let sourceImage: CGImage = loadSourceIcon(appPath: gameAppPath)
let source: PixelBuffer = PixelBuffer(image: sourceImage, width: 512, height: 512)
let shipMask: [Bool] = cutOutShip(source)
let ship: PixelBuffer = makeShipLayer(source: source, mask: shipMask, size: Int(canvasSize))
let blueprint: PixelBuffer = makeBlueprintLayer(ship: ship)
let splitShip: PixelBuffer = makeSplitShip(ship: ship, blueprint: blueprint)
let icon: CGImage = renderIcon(shipLayer: splitShip.makeImage())

let iconSetFolder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
writeIconSet(icon, to: iconSetFolder)
runIconutil(iconSet: iconSetFolder, output: scriptFolder.appendingPathComponent("AppIcon.icns"))
writePNG(icon, size: 1024, to: scriptFolder.appendingPathComponent("AppIcon.png"))
try? FileManager.default.removeItem(at: iconSetFolder)

print("Wrote \(scriptFolder.appendingPathComponent("AppIcon.icns").path)")
