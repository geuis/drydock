import AppKit
import CoreText
import SwiftUI

// System names for the galaxy map, laid out once and drawn with Core Text.
//
// Drawing 545 names as SwiftUI Text inside the Canvas took about 66 ms per
// redraw, which made dragging the map choppy; the same names as prebuilt
// Core Text lines draw in a few milliseconds. Layout (including the overlap
// check) only changes with zoom, markers, or selection, so it's cached.
final class GalaxyLabelLayout {
    // A system's name set in one font, with its measurements.
    struct MeasuredLine {
        let line: CTLine
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat

        init(_ text: NSAttributedString) {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let line: CTLine = CTLineCreateWithAttributedString(text)

            self.line = line
            self.width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            self.ascent = ascent
            self.descent = descent
        }
    }

    struct PlacedLabel {
        let line: CTLine
        // Where the text's baseline starts, in chart coordinates.
        let baselineOrigin: CGPoint
    }

    struct Key: Equatable {
        let geometry: GalaxyGeometry
        let markers: [Int: [MissionMapLocation.Role]]
        let selectedSystemID: Int?
        let currentSystemID: Int?
    }

    let key: Key
    let labels: [PlacedLabel]

    private static let starRadius: CGFloat = 3.5

    init(galaxy: GalaxyMap, key: Key, measure: (StarSystemDefinition, Bool) -> MeasuredLine) {
        self.key = key
        self.labels = Self.place(galaxy: galaxy, key: key, measure: measure)
    }

    // Every system is named, but a name that would overlap one already
    // placed waits until zooming in makes room; overlapping text can't be
    // read anyway. Marked and selected systems go first so theirs always
    // show, as does the player's own system.
    private static func place(galaxy: GalaxyMap, key: Key, measure: (StarSystemDefinition, Bool) -> MeasuredLine) -> [PlacedLabel] {
        let isMarked: (StarSystemDefinition) -> Bool = { system in
            system.id == key.selectedSystemID || system.id == key.currentSystemID || !(key.markers[system.id] ?? []).isEmpty
        }

        let ordered: [StarSystemDefinition] = galaxy.systems.filter(isMarked) + galaxy.systems.filter { !isMarked($0) }

        var taken = OccupiedAreas()
        var placed: [PlacedLabel] = []

        for system in ordered {
            let emphasized: Bool = isMarked(system)
            let measured: MeasuredLine = measure(system, emphasized)
            let ascent: CGFloat = measured.ascent
            let descent: CGFloat = measured.descent

            let center: CGPoint = key.geometry.point(of: system)
            let ringCount: Int = (key.markers[system.id]?.count ?? 0) + (system.id == key.currentSystemID ? 1 : 0)
            let left: CGFloat = center.x + starRadius + 3 + CGFloat(ringCount) * 4
            let frame = CGRect(x: left, y: center.y - (ascent + descent) / 2, width: measured.width, height: ascent + descent)

            guard emphasized || !taken.intersects(frame) else { continue }

            taken.insert(frame.insetBy(dx: -2, dy: 0))
            placed.append(PlacedLabel(line: measured.line, baselineOrigin: CGPoint(x: left, y: frame.minY + ascent)))
        }

        return placed
    }

    // Placed label frames, bucketed into a coarse grid so each new label is
    // only checked against its neighbours rather than every label so far.
    private struct OccupiedAreas {
        private static let cellSize: CGFloat = 64

        private struct Cell: Hashable {
            let column: Int
            let row: Int
        }

        private var framesByCell: [Cell: [CGRect]] = [:]

        func intersects(_ frame: CGRect) -> Bool {
            Self.cells(covering: frame).contains { cell in
                framesByCell[cell]?.contains { $0.intersects(frame) } ?? false
            }
        }

        mutating func insert(_ frame: CGRect) {
            for cell in Self.cells(covering: frame) {
                framesByCell[cell, default: []].append(frame)
            }
        }

        private static func cells(covering frame: CGRect) -> [Cell] {
            let firstColumn: Int = Int((frame.minX / cellSize).rounded(.down))
            let lastColumn: Int = Int((frame.maxX / cellSize).rounded(.down))
            let firstRow: Int = Int((frame.minY / cellSize).rounded(.down))
            let lastRow: Int = Int((frame.maxY / cellSize).rounded(.down))

            var cells: [Cell] = []

            for column in firstColumn...lastColumn {
                for row in firstRow...lastRow {
                    cells.append(Cell(column: column, row: row))
                }
            }

            return cells
        }
    }

    // A little larger when zoomed in, never too small to read. Rounded to
    // half points so zooming reuses measured lines instead of setting new
    // text for every tiny zoom change.
    static func fontSize(zoom: Double) -> CGFloat {
        let size: CGFloat = min(max(9 + CGFloat(zoom) * 2, 9), 13)
        return (size * 2).rounded() / 2
    }

    static func attributes(baseSize: CGFloat, emphasized: Bool) -> [NSAttributedString.Key: Any] {
        let font: NSFont = NSFont.systemFont(ofSize: emphasized ? baseSize + 2 : baseSize, weight: emphasized ? .semibold : .regular)
        let color: CGColor = emphasized ? NSColor.white.cgColor : NSColor(white: 0.7, alpha: 1).cgColor

        // Core Text reads its own colour key, not AppKit's.
        return [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
    }

    func draw(in context: GraphicsContext) {
        context.withCGContext { cgContext in
            // The Canvas is flipped (y grows down), so flip glyphs back
            // upright.
            cgContext.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

            for label in labels {
                cgContext.textPosition = label.baselineOrigin
                CTLineDraw(label.line, cgContext)
            }
        }
    }
}

// Keeps the last layout so rebuilding the chart while dragging (which
// happens every frame) reuses it instead of laying out again, and keeps
// measured names per font size so zooming only redoes placement.
final class GalaxyLabelCache {
    private struct LineKey: Hashable {
        let systemID: Int
        let fontSize: CGFloat
        let emphasized: Bool
    }

    private var layout: GalaxyLabelLayout?
    private var lines: [LineKey: GalaxyLabelLayout.MeasuredLine] = [:]

    func layout(galaxy: GalaxyMap, key: GalaxyLabelLayout.Key) -> GalaxyLabelLayout {
        if let layout, layout.key == key {
            return layout
        }

        let fontSize: CGFloat = GalaxyLabelLayout.fontSize(zoom: key.geometry.zoom)
        let fresh = GalaxyLabelLayout(galaxy: galaxy, key: key) { system, emphasized in
            measuredLine(system, fontSize: fontSize, emphasized: emphasized)
        }

        layout = fresh
        return fresh
    }

    private func measuredLine(_ system: StarSystemDefinition, fontSize: CGFloat, emphasized: Bool) -> GalaxyLabelLayout.MeasuredLine {
        let lineKey = LineKey(systemID: system.id, fontSize: fontSize, emphasized: emphasized)

        if let cached = lines[lineKey] {
            return cached
        }

        let text = NSAttributedString(string: GameName(system.name).title, attributes: GalaxyLabelLayout.attributes(baseSize: fontSize, emphasized: emphasized))
        let measured = GalaxyLabelLayout.MeasuredLine(text)
        lines[lineKey] = measured
        return measured
    }
}
