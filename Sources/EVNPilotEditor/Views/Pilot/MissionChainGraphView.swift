import AppKit
import SwiftUI

// A story chain drawn as a top-to-bottom flowchart, like the classic EV
// Nova walkthroughs: one box per mission, lines for what leads to what, and
// alternate tracks side by side. Box colors show the pilot's progress, so
// "how far along am I, and where did it stop?" reads at a glance.
//
// The chart is a flat surface the player drags around (PanSurface) rather
// than a scroll view. Dragging only moves the already-drawn chart
// (ChainChart), which redraws only when the chain, zoom, selection, or a
// mission's status changes; redrawing 80+ boxes per mouse move was laggy.
struct MissionChainGraphView: View {
    let chain: MissionChainComponent
    let snapshot: GameDataSnapshot
    let diagnostics: MissionDiagnostics?
    // Where the chain actually stops (the chain summary's first blocked
    // missions). Blocked missions further on are only waiting their turn.
    let stuckMissionIDs: Set<Int>
    @Binding var selectedMissionID: Int?

    @State private var zoom: Double = 1.0
    @State private var prepared: PreparedChart?
    @State private var focusRequest: PanSurface<ChainChart>.FocusRequest?
    @State private var startRequest: Int = 0
    // Clicking a box selects it without moving the chart; only selections
    // from elsewhere (links in the details pane) bring a box into view.
    @State private var clickedMissionID: Int?

    private static let zoomLevels: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5]

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            if let prepared, prepared.chainID == chain.id {
                let geometry = ChartGeometry(layout: prepared.layout, zoom: zoom)
                // Worked out here, not inside the content closure, which
                // runs on every drag step.
                let statuses: [Int: NodeStatus] = nodeStatuses(prepared)
                let selected: Int? = selectedMissionID

                PanSurface(
                    contentSize: geometry.contentSize,
                    startPoint: CGPoint(x: geometry.columnX(prepared.layout.startColumn), y: 0),
                    zoom: zoom,
                    resetKey: chain.id,
                    startRequest: startRequest,
                    focusRequest: $focusRequest,
                    onBackgroundClick: { selectedMissionID = nil }
                ) {
                    ChainChart(
                        prepared: prepared,
                        geometry: geometry,
                        statuses: statuses,
                        selectedMissionID: selected,
                        onSelect: select
                    )
                }
            } else {
                Color.clear
            }
        }
        .onChange(of: chain.id, initial: true) { _, _ in
            prepared = PreparedChart(chain: chain, resolver: snapshot.missionResolver)
        }
        .onChange(of: selectedMissionID) { _, newValue in
            guard let newValue, newValue != clickedMissionID, let prepared else { return }

            let geometry = ChartGeometry(layout: prepared.layout, zoom: zoom)

            if let center = geometry.center(of: newValue) {
                focusRequest = .init(point: center)
            }
        }
    }

    private func select(_ missionID: Int) {
        clickedMissionID = missionID
        selectedMissionID = selectedMissionID == missionID ? nil : missionID
    }

    // Status per box, with blocked missions past the stuck point shown as
    // "not reached yet" instead of another orange warning.
    private func nodeStatuses(_ prepared: PreparedChart) -> [Int: NodeStatus] {
        var statuses: [Int: NodeStatus] = [:]

        for missionID in prepared.missionsByID.keys {
            guard let status = diagnostics?.diagnosis(for: missionID)?.status else { continue }

            statuses[missionID] = status == .blocked && !stuckMissionIDs.contains(missionID) ? .notReached : .status(status)
        }

        return statuses
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            legendLine("Completed leads to", style: .completed)
            legendLine("Unlocked by a story flag", style: .flag)
            legendLine("Refused, failed, or aborted", style: .other)

            Label("Not reached yet", systemImage: "circle")
                .foregroundStyle(.secondary)

            Spacer()

            Text("Drag to move around")
                .foregroundStyle(.tertiary)

            Button {
                startRequest += 1
            } label: {
                Label("Start", systemImage: "arrow.up.to.line")
            }
            .help("Back to where the story starts")

            Button {
                zoom = Self.zoomLevels.last { $0 < zoom } ?? zoom
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")
            .disabled(zoom <= Self.zoomLevels.first ?? zoom)

            Text("\(Int(zoom * 100))%")
                .monospacedDigit()
                .frame(width: 40)

            Button {
                zoom = Self.zoomLevels.first { $0 > zoom } ?? zoom
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in")
            .disabled(zoom >= Self.zoomLevels.last ?? zoom)
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func legendLine(_ title: String, style: LinkStyle) -> some View {
        HStack(spacing: 4) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 5))
                path.addLine(to: CGPoint(x: 22, y: 5))
            }
            .stroke(style.color, style: style.strokeStyle(width: 2))
            .frame(width: 22, height: 10)

            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Prepared data

// Everything about a chain's chart that doesn't depend on the pilot, worked
// out once per chain rather than on every redraw.
struct PreparedChart {
    let chainID: Int
    let layout: MissionChainLayout
    let missions: [MissionDefinition]
    let missionsByID: [Int: MissionDefinition]
    let linkStyles: [MissionChainLayout.Link: LinkStyle]

    init(chain: MissionChainComponent, resolver: MissionChainResolver) {
        let layout = MissionChainLayout(chain: chain, resolver: resolver)
        let missionsByID: [Int: MissionDefinition] = Dictionary(chain.missions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var linkStyles: [MissionChainLayout.Link: LinkStyle] = [:]

        for link in layout.links {
            guard let source = missionsByID[link.fromID] else { continue }
            linkStyles[link] = LinkStyle(from: source, to: link.toID, resolver: resolver)
        }

        self.chainID = chain.id
        self.layout = layout
        self.missions = chain.missions
        self.missionsByID = missionsByID
        self.linkStyles = linkStyles
    }
}

enum NodeStatus: Equatable {
    case status(MissionStatus)
    case notReached
}

// Where boxes and lines go, at a given zoom.
struct ChartGeometry: Equatable {
    static let nodeWidth: CGFloat = 210
    static let nodeHeight: CGFloat = 54
    static let columnGap: CGFloat = 34
    static let rowGap: CGFloat = 44
    static let margin: CGFloat = 24

    let layout: MissionChainLayout
    let zoom: Double

    var nodeSize: CGSize {
        CGSize(width: Self.nodeWidth * zoom, height: Self.nodeHeight * zoom)
    }

    var contentSize: CGSize {
        let rows: CGFloat = CGFloat(max(layout.rowCount, 1))
        let hasLoops: Bool = layout.links.contains(where: \.loopsBack)

        // Extra room on the right for loop lines.
        let loopRoom: CGFloat = hasLoops ? Self.columnGap + 40 : 0
        let span: CGFloat = CGFloat(layout.maxColumn - layout.minColumn) * (Self.nodeWidth + Self.columnGap)
        let width: CGFloat = span + Self.nodeWidth + Self.margin * 2 + loopRoom
        let height: CGFloat = rows * Self.nodeHeight + (rows - 1) * Self.rowGap + Self.margin * 2

        return CGSize(width: width * zoom, height: height * zoom)
    }

    // Horizontal centre of a layout column.
    func columnX(_ column: Double) -> CGFloat {
        let step: CGFloat = Self.nodeWidth + Self.columnGap
        return (Self.margin + Self.nodeWidth / 2 + CGFloat(column - layout.minColumn) * step) * zoom
    }

    func center(of missionID: Int) -> CGPoint? {
        guard let placement = layout.placements[missionID] else { return nil }

        let y: CGFloat = Self.margin + Self.nodeHeight / 2 + CGFloat(placement.row) * (Self.nodeHeight + Self.rowGap)
        return CGPoint(x: columnX(placement.column), y: y * zoom)
    }
}

// MARK: - Chart

// The boxes and lines, drawn at full size. Equatable so dragging (which
// never changes these inputs) doesn't redraw it.
struct ChainChart: View, Equatable {
    let prepared: PreparedChart
    let geometry: ChartGeometry
    let statuses: [Int: NodeStatus]
    let selectedMissionID: Int?
    let onSelect: (Int) -> Void

    static func == (lhs: ChainChart, rhs: ChainChart) -> Bool {
        lhs.prepared.chainID == rhs.prepared.chainID
            && lhs.geometry == rhs.geometry
            && lhs.statuses == rhs.statuses
            && lhs.selectedMissionID == rhs.selectedMissionID
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            linkLayer

            ForEach(prepared.missions, id: \.id) { mission in
                if let center = geometry.center(of: mission.id) {
                    node(mission)
                        .position(center)
                }
            }
        }
        .frame(width: geometry.contentSize.width, height: geometry.contentSize.height)
    }

    // MARK: Nodes

    private func node(_ mission: MissionDefinition) -> some View {
        let zoom: Double = geometry.zoom
        let name: GameName = GameName(mission.name)
        let nodeStatus: NodeStatus? = statuses[mission.id]
        let isNotReached: Bool = nodeStatus == .notReached
        let status: MissionStatus? = { if case .status(let value) = nodeStatus { return value } else { return nil } }()
        let color: Color = isNotReached ? .secondary : (status?.color ?? .secondary)
        let symbol: String? = isNotReached ? "circle" : status?.symbolName
        let statusText: String? = isNotReached ? "Not reached yet" : status?.displayName
        let isSelected: Bool = selectedMissionID == mission.id

        return Button {
            onSelect(mission.id)
        } label: {
            VStack(alignment: .leading, spacing: 2 * zoom) {
                HStack(spacing: 5 * zoom) {
                    if let symbol {
                        Image(systemName: symbol)
                            .foregroundStyle(color)
                    }

                    Text(name.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .font(.system(size: 12 * zoom))

                Text([name.note, "#\(mission.id)"].compactMap { $0 }.joined(separator: "  "))
                    .font(.system(size: 10 * zoom))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8 * zoom)
            .frame(width: geometry.nodeSize.width, height: geometry.nodeSize.height, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8 * zoom)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8 * zoom)
                            .fill(color.opacity(status == .completed || isNotReached ? 0.06 : 0.16))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8 * zoom)
                    .stroke(isSelected ? Color.accentColor : color.opacity(0.8), lineWidth: isSelected ? 3 : 1.2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8 * zoom))
        }
        .buttonStyle(.plain)
        .help("\(name.full) (ID \(mission.id))\(statusText.map { ": \($0)" } ?? "")")
    }

    // MARK: Links

    private var linkLayer: some View {
        let selected: Int? = selectedMissionID
        let geometry: ChartGeometry = geometry
        let prepared: PreparedChart = prepared

        return Canvas { context, _ in
            // Selected mission's links last, so they draw on top.
            let touchesSelection: (MissionChainLayout.Link) -> Bool = { $0.fromID == selected || $0.toID == selected }
            let links: [MissionChainLayout.Link] = prepared.layout.links
            let ordered: [MissionChainLayout.Link] = links.filter { !touchesSelection($0) } + links.filter(touchesSelection)

            for link in ordered {
                guard let from = geometry.center(of: link.fromID), let to = geometry.center(of: link.toID) else { continue }

                let style: LinkStyle = prepared.linkStyles[link] ?? .completed
                let isHighlighted: Bool = touchesSelection(link)
                let color: Color = isHighlighted ? .accentColor : style.color
                let path: Path = Self.linkPath(from: from, to: to, loopsBack: link.loopsBack, geometry: geometry)

                context.stroke(path, with: .color(color), style: style.strokeStyle(width: isHighlighted ? 2.5 : 1.4))
                context.fill(Self.arrowHead(to: to, loopsBack: link.loopsBack, geometry: geometry), with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }

    // Down links run bottom edge to top edge. Loops leave from the right
    // side and come back into the target's right side.
    private static func linkPath(from: CGPoint, to: CGPoint, loopsBack: Bool, geometry: ChartGeometry) -> Path {
        let zoom: Double = geometry.zoom
        let halfWidth: CGFloat = geometry.nodeSize.width / 2
        let halfHeight: CGFloat = geometry.nodeSize.height / 2

        var path = Path()

        if loopsBack {
            let start = CGPoint(x: from.x + halfWidth, y: from.y)
            let end = CGPoint(x: to.x + halfWidth + 8 * zoom, y: to.y)
            let bulge: CGFloat = (ChartGeometry.columnGap + 30) * zoom

            path.move(to: start)
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x + bulge, y: start.y),
                control2: CGPoint(x: end.x + bulge, y: end.y)
            )
        } else {
            let start = CGPoint(x: from.x, y: from.y + halfHeight)
            let end = CGPoint(x: to.x, y: to.y - halfHeight - 6 * zoom)
            let bend: CGFloat = max((end.y - start.y) / 2, 20 * zoom)

            path.move(to: start)
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x, y: start.y + bend),
                control2: CGPoint(x: end.x, y: end.y - bend)
            )
        }

        return path
    }

    private static func arrowHead(to: CGPoint, loopsBack: Bool, geometry: ChartGeometry) -> Path {
        let size: CGFloat = 6 * geometry.zoom
        var path = Path()

        if loopsBack {
            // Loops arrive from the right, pointing left.
            let tip = CGPoint(x: to.x + geometry.nodeSize.width / 2, y: to.y)
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x + size * 1.3, y: tip.y - size))
            path.addLine(to: CGPoint(x: tip.x + size * 1.3, y: tip.y + size))
        } else {
            let tip = CGPoint(x: to.x, y: to.y - geometry.nodeSize.height / 2)
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x - size, y: tip.y - size * 1.3))
            path.addLine(to: CGPoint(x: tip.x + size, y: tip.y - size * 1.3))
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Pan surface

// Shows a large piece of content through a window the player drags around
// (or moves with a trackpad or mouse wheel). Owns the pan position itself,
// so moving only repositions the content instead of rebuilding it.
struct PanSurface<Content: View & Equatable>: View {
    struct FocusRequest: Equatable {
        let id = UUID()
        // Point in content coordinates to bring to the middle of the view.
        let point: CGPoint
    }

    let contentSize: CGSize
    // Point in content coordinates to put at the top centre on "start".
    let startPoint: CGPoint
    // Put the start point in the middle of the view instead, for content
    // without a natural top (the galaxy map).
    var centersStart: Bool = false
    // When set, the mouse wheel and two-finger swipes zoom (around the
    // pointer) instead of moving the content.
    var scrollZoom: Binding<Double>? = nil
    var zoomRange: ClosedRange<Double> = 0.1...4
    let zoom: Double
    // Changing this (a new chain) goes back to the start.
    let resetKey: Int
    // Incremented by the Start button.
    let startRequest: Int
    @Binding var focusRequest: FocusRequest?
    let onBackgroundClick: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var pan: CGSize = .zero
    @State private var panAtDragStart: CGSize?
    @State private var viewportSize: CGSize = .zero
    @State private var isHovering = false
    @State private var hoverLocation: CGPoint?
    // Point in the view that stays put through the next zoom change.
    @State private var zoomAnchor: CGPoint?
    @State private var scrollMonitor: Any?
    // Until the player moves the chart, keep it centred on the start as the
    // window and panes settle into their sizes.
    @State private var hasMoved = false

    var body: some View {
        GeometryReader { proxy in
            content()
                .equatable()
                .offset(pan)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackgroundClick)
                .simultaneousGesture(dragGesture)
                .onHover { inside in
                    isHovering = inside

                    if inside {
                        NSCursor.openHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let location):
                        hoverLocation = location

                    case .ended:
                        hoverLocation = nil
                    }
                }
                .onChange(of: proxy.size, initial: true) { _, newSize in
                    viewportSize = newSize

                    if !hasMoved {
                        showStart()
                    }
                }
        }
        .onChange(of: resetKey) { _, _ in
            hasMoved = false
            showStart()
        }
        .onChange(of: startRequest) { _, _ in
            hasMoved = false

            withAnimation(.easeInOut(duration: 0.3)) {
                showStart()
            }
        }
        .onChange(of: focusRequest) { _, request in
            guard let request else { return }

            hasMoved = true

            withAnimation(.easeInOut(duration: 0.3)) {
                pan = clamped(CGSize(width: viewportSize.width / 2 - request.point.x, height: viewportSize.height / 2 - request.point.y))
            }

            focusRequest = nil
        }
        .onChange(of: zoom) { oldZoom, newZoom in
            keepCenterWhileZooming(from: oldZoom, to: newZoom)
        }
        .onAppear(perform: startWheelPanning)
        .onDisappear(perform: stopWheelPanning)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if panAtDragStart == nil {
                    panAtDragStart = pan
                    hasMoved = true
                    NSCursor.closedHand.push()
                }

                let start: CGSize = panAtDragStart ?? pan
                pan = clamped(CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height))
            }
            .onEnded { _ in
                panAtDragStart = nil
                NSCursor.pop()
            }
    }

    // Two-finger trackpad swipes and mouse wheels move the content too, but
    // only while the pointer is over it.
    private func startWheelPanning() {
        guard scrollMonitor == nil else { return }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard isHovering else { return event }

            if let scrollZoom {
                zoom(scrollZoom, by: event)
                return nil
            }

            // Mouse wheels report lines, trackpads report points.
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            hasMoved = true
            pan = clamped(CGSize(width: pan.width + event.scrollingDeltaX * scale, height: pan.height + event.scrollingDeltaY * scale))
            return nil
        }
    }

    private func zoom(_ binding: Binding<Double>, by event: NSEvent) {
        // Trackpads send many small deltas, mouse wheels a few big ones.
        let sensitivity: Double = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
        let factor: Double = exp(Double(event.scrollingDeltaY) * sensitivity)
        let newZoom: Double = min(max(binding.wrappedValue * factor, zoomRange.lowerBound), zoomRange.upperBound)

        guard newZoom != binding.wrappedValue else { return }

        hasMoved = true
        zoomAnchor = hoverLocation
        binding.wrappedValue = newZoom
    }

    private func stopWheelPanning() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }

        scrollMonitor = nil
    }

    private func showStart() {
        let top: CGFloat = centersStart ? viewportSize.height / 2 - startPoint.y : -startPoint.y
        pan = clamped(CGSize(width: viewportSize.width / 2 - startPoint.x, height: top))
    }

    // Keeps at least half the view covered by content, so it can't be lost.
    private func clamped(_ offset: CGSize) -> CGSize {
        let minX: CGFloat = viewportSize.width / 2 - contentSize.width
        let minY: CGFloat = viewportSize.height / 2 - contentSize.height
        let maxX: CGFloat = viewportSize.width / 2
        let maxY: CGFloat = viewportSize.height / 2

        return CGSize(
            width: min(max(offset.width, minX), maxX),
            height: min(max(offset.height, minY), maxY)
        )
    }

    // Everything scales with zoom, so scaling the distance from the anchor
    // (the pointer for wheel zoom, otherwise the view's centre) keeps
    // whatever is there in place. Until the player moves, the start stays
    // where it was put instead.
    private func keepCenterWhileZooming(from oldZoom: Double, to newZoom: Double) {
        guard hasMoved else {
            showStart()
            return
        }

        let ratio: CGFloat = newZoom / oldZoom
        let anchor: CGPoint = zoomAnchor ?? CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        zoomAnchor = nil

        pan = clamped(CGSize(
            width: anchor.x - (anchor.x - pan.width) * ratio,
            height: anchor.y - (anchor.y - pan.height) * ratio
        ))
    }
}

// MARK: - Link style

// How a link is drawn, from how the earlier mission leads to the later one.
enum LinkStyle {
    case completed
    case flag
    case other

    init(from mission: MissionDefinition, to targetID: Int, resolver: MissionChainResolver) {
        if mission.successMissionIDs.contains(targetID) || mission.acceptMissionIDs.contains(targetID) {
            self = .completed
        } else if resolver.unlockFlag(from: mission, to: targetID) != nil {
            self = .flag
        } else {
            self = .other
        }
    }

    var color: Color {
        switch self {
        case .completed, .flag: return .secondary
        case .other: return .orange
        }
    }

    func strokeStyle(width: CGFloat) -> StrokeStyle {
        switch self {
        case .completed: return StrokeStyle(lineWidth: width, lineCap: .round)
        case .flag: return StrokeStyle(lineWidth: width, lineCap: .round, dash: [5, 4])
        case .other: return StrokeStyle(lineWidth: width, lineCap: .round, dash: [2, 3])
        }
    }
}
