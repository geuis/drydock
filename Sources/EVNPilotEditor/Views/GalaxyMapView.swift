import SwiftUI

// The Map tab: every star system at its in-game map position, joined by its
// hyperlinks. Search finds a system or planet; "Find on Map" on a mission
// marks where it's offered, where it goes, and where its special ships are.
struct GalaxyMapView: View {
    @EnvironmentObject private var gameData: GameDataStore

    var body: some View {
        if let snapshot = gameData.snapshot {
            GalaxyMapBrowser(snapshot: snapshot)
        } else if gameData.isLoading {
            ProgressView("Loading game data…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Game Data Unavailable",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(gameData.errorMessage ?? "Set the Nova Files folder in Settings, then restart the app.")
            )
        }
    }
}

// MARK: - Browser

private struct GalaxyMapBrowser: View {
    let snapshot: GameDataSnapshot

    @EnvironmentObject private var navigator: AppNavigator

    // Replaced by the fit-the-whole-galaxy zoom once the view has a size.
    @State private var zoom: Double = 0.3
    // The last zoom set to fit the view. While zoom still equals it, the
    // player hasn't zoomed, so resizes (including the window growing to
    // fill the screen after launch) fit again.
    @State private var fittedZoom: Double?
    @State private var viewportSize: CGSize = .zero
    @State private var searchText: String = ""
    @State private var selectedSystemID: Int?
    @State private var focusRequest: PanSurface<GalaxyChart>.FocusRequest?
    // Galaxy coordinates the map opens on; moved by "Find on Map". Bumping
    // homeGeneration makes the pan surface go back to it.
    @State private var homePoint: CGPoint?
    @State private var homeGeneration: Int = 0
    @State private var labelCache: GalaxyLabelCache = GalaxyLabelCache()

    private static let zoomRange: ClosedRange<Double> = 0.1...3
    private static let zoomStep: Double = 1.25

    private var galaxy: GalaxyMap {
        snapshot.galaxy
    }

    private var geometry: GalaxyGeometry {
        GalaxyGeometry(galaxy: galaxy, zoom: zoom)
    }

    // The system holding the open pilot's last planet or station.
    private var currentSystemID: Int? {
        navigator.pilotLocation.flatMap { galaxy.systemID(containingStellar: $0.stellarID) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                toolbar

                Divider()

                chartSurface
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            sidebar
                .frame(minWidth: 240, idealWidth: 290, maxWidth: 380, maxHeight: .infinity)
        }
        .onChange(of: navigator.mapFocus?.id, initial: true) { _, _ in
            applyMissionFocus()
        }
    }

    // MARK: Chart

    private var chartSurface: some View {
        let geometry: GalaxyGeometry = geometry
        let home: CGPoint = homePoint ?? galaxy.centerPoint

        return GeometryReader { proxy in
            PanSurface(
                contentSize: geometry.contentSize,
                startPoint: geometry.point(x: home.x, y: home.y),
                centersStart: true,
                scrollZoom: $zoom,
                zoomRange: Self.zoomRange,
                zoom: zoom,
                resetKey: homeGeneration,
                startRequest: 0,
                focusRequest: $focusRequest,
                onBackgroundClick: { selectedSystemID = nil }
            ) {
                let markers: [Int: [MissionMapLocation.Role]] = markersBySystem
                let labelKey = GalaxyLabelLayout.Key(geometry: geometry, markers: markers, selectedSystemID: selectedSystemID, currentSystemID: currentSystemID)

                GalaxyChart(
                    galaxy: galaxy,
                    geometry: geometry,
                    markers: markers,
                    selectedSystemID: selectedSystemID,
                    currentSystemID: currentSystemID,
                    labels: labelCache.layout(galaxy: galaxy, key: labelKey),
                    onSelect: { systemID in
                        selectedSystemID = systemID
                    }
                )
            }
            .onChange(of: proxy.size, initial: true) { _, newSize in
                viewportSize = newSize

                let playerHasZoomed: Bool = fittedZoom != nil && fittedZoom != zoom

                if !playerHasZoomed && newSize.width > 0 && newSize.height > 0 {
                    fitWholeGalaxy()
                }
            }
        }
        .background(GalaxyChart.backgroundColor)
    }

    private func fitWholeGalaxy() {
        zoom = fittingZoom
        fittedZoom = zoom
    }

    // The zoom that shows the whole galaxy in the view.
    private var fittingZoom: Double {
        let fullSize: CGSize = GalaxyGeometry(galaxy: galaxy, zoom: 1).contentSize
        guard fullSize.width > 0, fullSize.height > 0, viewportSize.width > 0, viewportSize.height > 0 else { return zoom }

        let fit: Double = min(viewportSize.width / fullSize.width, viewportSize.height / fullSize.height)
        return min(max(fit, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            ForEach(MissionMapLocation.Role.allCases, id: \.self) { role in
                HStack(spacing: 4) {
                    Circle()
                        .stroke(role.color, lineWidth: 2)
                        .frame(width: 10, height: 10)

                    Text(role.rawValue)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 4) {
                Circle()
                    .stroke(GalaxyChart.currentSystemColor, lineWidth: 3)
                    .frame(width: 10, height: 10)

                Text("You are here")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Drag to move, scroll to zoom")
                .foregroundStyle(.tertiary)

            Button {
                if let currentSystemID {
                    show(systemIDs: [currentSystemID], selecting: currentSystemID)
                }
            } label: {
                Label("My System", systemImage: "location")
            }
            .help("Show the system the open pilot is in")
            .disabled(currentSystemID == nil)

            Button {
                homePoint = nil
                fitWholeGalaxy()
                homeGeneration += 1
            } label: {
                Label("Whole Map", systemImage: "scope")
            }
            .help("Zoom out to show the whole galaxy")

            Button {
                zoom = max(zoom / Self.zoomStep, Self.zoomRange.lowerBound)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")
            .disabled(zoom <= Self.zoomRange.lowerBound)

            Text("\(Int(zoom * 100))%")
                .monospacedDigit()
                .frame(width: 40)

            Button {
                zoom = min(zoom * Self.zoomStep, Self.zoomRange.upperBound)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in")
            .disabled(zoom >= Self.zoomRange.upperBound)
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            TextField("Search systems and planets", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(10)

            Divider()

            if !trimmedQuery.isEmpty {
                searchResultsList
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let focus = navigator.mapFocus {
                            missionPanel(focus)
                        }

                        if let systemID = selectedSystemID, let system = galaxy.systemsByID[systemID] {
                            systemPanel(system)
                        } else if navigator.mapFocus == nil {
                            Text("Search for a system or planet, or click a star. Use \"Find on Map\" on a mission in Story Chains or Current Missions to mark where it takes place.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var searchResultsList: some View {
        let results: [MapSearchResult] = MapSearchResult.search(trimmedQuery, galaxy: galaxy, names: snapshot.names)

        return List(results) { result in
            Button {
                searchText = ""
                show(systemIDs: [result.systemID], selecting: result.systemID)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title)
                        .lineLimit(1)

                    Text(result.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if results.isEmpty {
                Text("No systems or planets match.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func missionPanel(_ focus: MapFocus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(focus.title)
                        .font(.headline)

                    Text("Mission \(focus.missionID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Clear") {
                    navigator.mapFocus = nil
                }
                .controlSize(.small)
            }

            ForEach(focus.locations) { location in
                locationRow(location)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func locationRow(_ location: MissionMapLocation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .stroke(location.role.color, lineWidth: 2.5)
                .frame(width: 11, height: 11)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(location.role.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(location.role.color)

                Text(location.description)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                locationSystemsLine(location)
            }
        }
    }

    @ViewBuilder
    private func locationSystemsLine(_ location: MissionMapLocation) -> some View {
        switch location.systemIDs.count {
        case 0:
            Text("Not one fixed place, so nothing is marked.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case 1:
            Button("Show \(systemTitle(location.systemIDs[0]))") {
                show(systemIDs: location.systemIDs, selecting: location.systemIDs[0])
            }
            .buttonStyle(.link)
            .font(.caption)

        default:
            Button("Show \(location.systemIDs.count) possible systems") {
                show(systemIDs: location.systemIDs, selecting: nil)
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    private func systemPanel(_ system: StarSystemDefinition) -> some View {
        let name: GameName = GameName(system.name)

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name.title)
                    .font(.title3.weight(.semibold))

                Text([name.note, "System \(system.id)"].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if system.id == currentSystemID, let location = navigator.pilotLocation {
                Label("\(location.pilotName) is here (last landed on \(stellarTitle(location.stellarID)))", systemImage: "location.fill")
                    .foregroundStyle(GalaxyChart.currentSystemColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LabeledContent("Government", value: governmentTitle(system.governmentID))

            if let roles = markersBySystem[system.id], !roles.isEmpty {
                LabeledContent("This mission", value: roles.map(\.rawValue).joined(separator: ", "))
            }

            detailList("Planets & Stations", emptyText: "None") {
                ForEach(system.stellarIDs, id: \.self) { stellarID in
                    Text(stellarTitle(stellarID))
                }
            } isEmpty: {
                system.stellarIDs.isEmpty
            }

            let neighborIDs: [Int] = galaxy.neighborIDs(of: system.id)

            detailList("Hyperlinks", emptyText: "None") {
                ForEach(neighborIDs, id: \.self) { neighborID in
                    Button(systemTitle(neighborID)) {
                        show(systemIDs: [neighborID], selecting: neighborID)
                    }
                    .buttonStyle(.link)
                }
            } isEmpty: {
                neighborIDs.isEmpty
            }
        }
    }

    private func detailList<Rows: View>(_ title: String, emptyText: String, @ViewBuilder rows: () -> Rows, isEmpty: () -> Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if isEmpty() {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else {
                rows()
            }
        }
    }

    // MARK: Focus

    // Each system's roles in the focused mission, for the chart's rings.
    private var markersBySystem: [Int: [MissionMapLocation.Role]] {
        var result: [Int: [MissionMapLocation.Role]] = [:]

        for location in navigator.mapFocus?.locations ?? [] {
            for systemID in location.systemIDs {
                result[systemID, default: []].append(location.role)
            }
        }

        return result
    }

    // Opens on the first place the mission marks, and selects it when it's
    // a single system.
    private func applyMissionFocus() {
        guard let focus = navigator.mapFocus else { return }
        guard let first = focus.locations.first(where: { !$0.systemIDs.isEmpty }) else { return }

        homePoint = galaxy.centroid(of: first.systemIDs)
        selectedSystemID = first.systemIDs.count == 1 ? first.systemIDs[0] : nil
        homeGeneration += 1
    }

    private func show(systemIDs: [Int], selecting systemID: Int?) {
        guard let center = galaxy.centroid(of: systemIDs) else { return }

        selectedSystemID = systemID
        focusRequest = PanSurface<GalaxyChart>.FocusRequest(point: geometry.point(x: center.x, y: center.y))
    }

    // MARK: Names

    private func systemTitle(_ systemID: Int) -> String {
        galaxy.systemsByID[systemID].map { GameName($0.name).title } ?? "System \(systemID)"
    }

    private func stellarTitle(_ stellarID: Int) -> String {
        snapshot.names.name(type: ResourceNameIndex.stellars, id: stellarID).map { GameName($0).title } ?? "Planet or station \(stellarID)"
    }

    private func governmentTitle(_ governmentID: Int?) -> String {
        guard let governmentID else { return "Independent" }
        return snapshot.names.name(type: ResourceNameIndex.governments, id: governmentID).map { GameName($0).title } ?? "Government \(governmentID)"
    }
}

// MARK: - Search

struct MapSearchResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemID: Int

    private static let limit: Int = 60

    // Systems first, then planets and stations, each matched on name or ID.
    static func search(_ query: String, galaxy: GalaxyMap, names: ResourceNameIndex) -> [MapSearchResult] {
        var results: [MapSearchResult] = []

        for system in galaxy.systems where matches(system.name, id: system.id, query: query) {
            let name: GameName = GameName(system.name)
            results.append(MapSearchResult(id: "system-\(system.id)", title: name.title, subtitle: ["System", name.note].compactMap { $0 }.joined(separator: " · "), systemID: system.id))
        }

        for entry in names.entries(ofType: ResourceNameIndex.stellars) where matches(entry.name, id: entry.id, query: query) {
            guard let systemID = galaxy.systemID(containingStellar: entry.id) else { continue }

            let systemTitle: String = galaxy.systemsByID[systemID].map { GameName($0.name).title } ?? "System \(systemID)"
            results.append(MapSearchResult(id: "stellar-\(entry.id)", title: GameName(entry.name).title, subtitle: "Planet or station in \(systemTitle)", systemID: systemID))
        }

        return Array(results.prefix(limit))
    }

    // Apostrophes are ignored on both sides, so "nilnesa" finds
    // "Nil'nesa" without the player guessing where the ' goes.
    static func matches(_ name: String, id: Int, query: String) -> Bool {
        let searchable: String = withoutApostrophes(GameName(name).title)
        let wanted: String = withoutApostrophes(query)

        return (!wanted.isEmpty && searchable.localizedCaseInsensitiveContains(wanted)) || String(id) == query
    }

    private static let apostrophes: Set<Character> = ["'", "\u{2019}", "\u{2018}", "`"]

    static func withoutApostrophes(_ text: String) -> String {
        String(text.filter { !apostrophes.contains($0) })
    }
}

// MARK: - Geometry

// Galaxy coordinates to chart points. The whole galaxy is scaled to a fixed
// width at 100% so plugin galaxies of any size come out usable.
struct GalaxyGeometry: Equatable {
    static let widthAtFullZoom: CGFloat = 2600
    static let margin: CGFloat = 80

    let zoom: Double
    let minX: CGFloat
    let minY: CGFloat
    let scale: CGFloat
    let contentSize: CGSize

    init(galaxy: GalaxyMap, zoom: Double) {
        let spanX: CGFloat = CGFloat(max(galaxy.maxX - galaxy.minX, 1))
        let spanY: CGFloat = CGFloat(max(galaxy.maxY - galaxy.minY, 1))
        let scale: CGFloat = Self.widthAtFullZoom / spanX * zoom

        self.zoom = zoom
        self.minX = CGFloat(galaxy.minX)
        self.minY = CGFloat(galaxy.minY)
        self.scale = scale
        self.contentSize = CGSize(width: spanX * scale + Self.margin * 2, height: spanY * scale + Self.margin * 2)
    }

    func point(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: (x - minX) * scale + Self.margin, y: (y - minY) * scale + Self.margin)
    }

    func point(of system: StarSystemDefinition) -> CGPoint {
        point(x: CGFloat(system.x), y: CGFloat(system.y))
    }
}

extension GalaxyMap {
    var centerPoint: CGPoint {
        CGPoint(x: CGFloat(minX + maxX) / 2, y: CGFloat(minY + maxY) / 2)
    }

    // Average position of some systems, in galaxy coordinates.
    func centroid(of systemIDs: [Int]) -> CGPoint? {
        let found: [StarSystemDefinition] = systemIDs.compactMap { systemsByID[$0] }
        guard !found.isEmpty else { return nil }

        let count: CGFloat = CGFloat(found.count)
        let x: CGFloat = found.reduce(0) { $0 + CGFloat($1.x) } / count
        let y: CGFloat = found.reduce(0) { $0 + CGFloat($1.y) } / count

        return CGPoint(x: x, y: y)
    }
}

extension MissionMapLocation.Role {
    var color: Color {
        switch self {
        case .offered: return .purple
        case .destination: return .orange
        case .returnTo: return .cyan
        case .specialShips: return .red
        }
    }
}

// MARK: - Chart

// Stars, hyperlinks, labels, and mission rings in one Canvas. Equatable so
// dragging the map (which changes none of these) doesn't redraw it.
struct GalaxyChart: View, Equatable {
    static let backgroundColor: Color = Color(white: 0.05)
    static let currentSystemColor: Color = .green

    let galaxy: GalaxyMap
    let geometry: GalaxyGeometry
    let markers: [Int: [MissionMapLocation.Role]]
    let selectedSystemID: Int?
    let currentSystemID: Int?
    let labels: GalaxyLabelLayout
    let onSelect: (Int?) -> Void

    private static let starRadius: CGFloat = 3.5
    private static let clickRadius: CGFloat = 14

    static func == (lhs: GalaxyChart, rhs: GalaxyChart) -> Bool {
        lhs.geometry == rhs.geometry
            && lhs.markers == rhs.markers
            && lhs.selectedSystemID == rhs.selectedSystemID
            && lhs.currentSystemID == rhs.currentSystemID
            && lhs.labels === rhs.labels
            && lhs.galaxy.systems.count == rhs.galaxy.systems.count
    }

    var body: some View {
        Canvas { context, _ in
            drawLinks(in: context)
            drawStars(in: context)
        }
        .frame(width: geometry.contentSize.width, height: geometry.contentSize.height)
        .gesture(SpatialTapGesture().onEnded { value in
            onSelect(nearestSystemID(to: value.location))
        })
    }

    private func drawLinks(in context: GraphicsContext) {
        var path = Path()

        for link in galaxy.links {
            guard let from = galaxy.systemsByID[link.fromID], let to = galaxy.systemsByID[link.toID] else { continue }

            path.move(to: geometry.point(of: from))
            path.addLine(to: geometry.point(of: to))
        }

        context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 1)
    }

    private func drawStars(in context: GraphicsContext) {
        for system in galaxy.systems {
            let center: CGPoint = geometry.point(of: system)
            let roles: [MissionMapLocation.Role] = markers[system.id] ?? []
            let isSelected: Bool = system.id == selectedSystemID

            drawRings(roles, around: center, in: context)

            // Outside the mission rings, so both stay visible.
            if system.id == currentSystemID {
                let radius: CGFloat = 7 + CGFloat(roles.count) * 4 + 1

                context.fill(circle(center, radius: radius), with: .color(Self.currentSystemColor.opacity(0.15)))
                context.stroke(circle(center, radius: radius), with: .color(Self.currentSystemColor), lineWidth: 3)
            }

            if isSelected {
                context.stroke(circle(center, radius: 7 + CGFloat(ringCount(system)) * 4 + 3), with: .color(.accentColor), lineWidth: 2.5)
            }

            let starColor: Color = isMarked(system) ? .white : Color(white: 0.75)
            context.fill(circle(center, radius: Self.starRadius), with: .color(starColor))
        }

        labels.draw(in: context)
    }

    private func isMarked(_ system: StarSystemDefinition) -> Bool {
        system.id == selectedSystemID || system.id == currentSystemID || !(markers[system.id] ?? []).isEmpty
    }

    // Mission rings plus the "you are here" ring.
    private func ringCount(_ system: StarSystemDefinition) -> Int {
        (markers[system.id]?.count ?? 0) + (system.id == currentSystemID ? 1 : 0)
    }

    // One ring per role, growing outward, so a system that's both the
    // destination and where the ships wait shows both colours.
    private func drawRings(_ roles: [MissionMapLocation.Role], around center: CGPoint, in context: GraphicsContext) {
        for (index, role) in roles.enumerated() {
            let radius: CGFloat = 7 + CGFloat(index) * 4

            context.fill(circle(center, radius: radius), with: .color(role.color.opacity(0.12)))
            context.stroke(circle(center, radius: radius), with: .color(role.color), lineWidth: 2)
        }
    }

    private func circle(_ center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func nearestSystemID(to location: CGPoint) -> Int? {
        var bestID: Int?
        var bestDistance: CGFloat = Self.clickRadius

        for system in galaxy.systems {
            let center: CGPoint = geometry.point(of: system)
            let distance: CGFloat = hypot(center.x - location.x, center.y - location.y)

            if distance <= bestDistance {
                bestDistance = distance
                bestID = system.id
            }
        }

        return bestID
    }
}
