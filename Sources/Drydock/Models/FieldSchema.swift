import Foundation

// Decoding wrapper matching the { "fields": [...] } top-level JSON shape used
// both by the bundled FieldSchema.json resource and the user-writable
// discovered-fields override file.
private struct FieldSchemaFile: Codable {
    var fields: [FieldDefinition]
}

public final class FieldSchema: ObservableObject {
    @Published public private(set) var fields: [FieldDefinition]

    // The ids that ship in Resources/FieldSchema.json, read from that file
    // so the list can't go stale. Anything else is treated as a
    // user-discovered field for persistence purposes.
    private let bundledFieldIDs: Set<String>

    public init(fields: [FieldDefinition], bundledFieldIDs: Set<String> = []) {
        self.fields = fields
        self.bundledFieldIDs = bundledFieldIDs
    }

    public static func loadDefault() -> FieldSchema {
        var loadedFields: [FieldDefinition] = []

        if let bundledFields = loadBundledFields() {
            loadedFields = bundledFields
        }

        let bundledIDs: Set<String> = Set(loadedFields.map(\.id))

        if let overrideFields = loadOverrideFields() {
            for field in overrideFields where !loadedFields.contains(where: { $0.id == field.id }) {
                loadedFields.append(field)
            }
        }

        return FieldSchema(fields: loadedFields, bundledFieldIDs: bundledIDs)
    }

    public func addDiscoveredField(_ field: FieldDefinition) {
        guard !fields.contains(where: { $0.id == field.id }) else {
            return
        }

        fields.append(field)
        persistDiscoveredFields()
    }

    func isBundledField(_ id: String) -> Bool {
        bundledFieldIDs.contains(id)
    }

    // MARK: - Loading

    private static func loadBundledFields() -> [FieldDefinition]? {
        guard let url = Bundle.module.url(forResource: "FieldSchema", withExtension: "json") else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(FieldSchemaFile.self, from: data)
            return file.fields
        } catch {
            return nil
        }
    }

    private static func loadOverrideFields() -> [FieldDefinition]? {
        guard let url = overrideFileURL() else {
            return nil
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(FieldSchemaFile.self, from: data)
            return file.fields
        } catch {
            return nil
        }
    }

    // MARK: - Persisting

    private func persistDiscoveredFields() {
        guard let url = FieldSchema.overrideFileURL() else {
            return
        }

        let discoveredFields = fields.filter { !isBundledField($0.id) }
        let file = FieldSchemaFile(fields: discoveredFields)

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(file)
            try data.write(to: url, options: .atomic)
        } catch {
            // Pragmatic best-effort persistence: a failure here should not
            // crash the app or lose the in-memory discovered field.
        }
    }

    private static func overrideFileURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        // Keeps the folder name from before the app was renamed Drydock, so
        // fields discovered by earlier versions are still found.
        return appSupport
            .appendingPathComponent("EVNPilotEditor")
            .appendingPathComponent("DiscoveredFields.json")
    }
}
