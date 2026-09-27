import XCTest
@testable import Drydock

final class GameDataLibraryTests: XCTestCase {
    // Builds a minimal BRGR .rez archive in the layout RezArchive reads:
    // little-endian headers and entry table, then a big-endian resource map.
    static func makeArchive(_ resources: [(type: String, id: Int16, name: String, data: Data)]) -> Data {
        var archive = Data()

        func appendLittle(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { archive.append(contentsOf: $0) }
        }

        func appendBig32(_ value: UInt32, to data: inout Data) {
            withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
        }

        let baseIndex: UInt32 = 1
        let entryCount: Int = resources.count + 1
        let dataStart: Int = 24 + entryCount * 12

        // Resource map: one type list entry per resource (types may repeat,
        // which the parser tolerates), then each type's one-entry list.
        var map = Data()
        let typeListOffset: UInt32 = 8
        appendBig32(typeListOffset, to: &map)
        appendBig32(UInt32(resources.count), to: &map)

        let resourceListsStart: Int = 8 + resources.count * 12

        for (index, resource) in resources.enumerated() {
            map.append(resource.type.data(using: .macOSRoman) ?? Data())
            appendBig32(UInt32(resourceListsStart + index * 266), to: &map)
            appendBig32(1, to: &map)
        }

        for (index, resource) in resources.enumerated() {
            appendBig32(baseIndex + UInt32(index), to: &map)
            map.append(resource.type.data(using: .macOSRoman) ?? Data())
            withUnsafeBytes(of: resource.id.bigEndian) { map.append(contentsOf: $0) }

            var name = resource.name.data(using: .macOSRoman) ?? Data()
            name.append(contentsOf: [UInt8](repeating: 0, count: 256 - name.count))
            map.append(name)
        }

        archive.append(Data("BRGR".utf8))
        appendLittle(1)
        appendLittle(12)
        appendLittle(1)
        appendLittle(baseIndex)
        appendLittle(UInt32(entryCount))

        var offset: Int = dataStart

        for resource in resources {
            appendLittle(UInt32(offset))
            appendLittle(UInt32(resource.data.count))
            appendLittle(0)
            offset += resource.data.count
        }

        appendLittle(UInt32(offset))
        appendLittle(UInt32(map.count))
        appendLittle(0)

        for resource in resources {
            archive.append(resource.data)
        }

        archive.append(map)
        return archive
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testLaterArchiveReplacesEarlierDuplicate() throws {
        let directory = try makeTempDirectory()

        try Self.makeArchive([
            (type: "sÿst", id: 128, name: "Sol", data: Data([1])),
            (type: "sÿst", id: 129, name: "Alpha", data: Data([2]))
        ]).write(to: directory.appendingPathComponent("A.rez"))

        try Self.makeArchive([
            (type: "sÿst", id: 128, name: "Sol (plug-in)", data: Data([3]))
        ]).write(to: directory.appendingPathComponent("B.rez"))

        let library = try GameDataLibrary(contentsOfDirectory: directory)
        let systems = library.resources(ofType: "sÿst")

        XCTAssertEqual(systems.map(\.id), [128, 129])
        XCTAssertEqual(library.resource(ofType: "sÿst", id: 128)?.name, "Sol (plug-in)")
        XCTAssertEqual(library.resource(ofType: "sÿst", id: 128)?.data, Data([3]))
        XCTAssertTrue(library.failedArchives.isEmpty)
    }

    func testPluginsInSubfoldersLoadAfterAndOverrideTheBaseGame() throws {
        let baseDirectory = try makeTempDirectory()
        let pluginsDirectory = try makeTempDirectory()
        let subfolder = pluginsDirectory.appendingPathComponent("Some Plug-in", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)

        // "Z" sorts after the plug-in's name, so only plug-in-last ordering
        // lets the plug-in win.
        try Self.makeArchive([
            (type: "mïsn", id: 200, name: "Base mission", data: Data([1]))
        ]).write(to: baseDirectory.appendingPathComponent("Z Data.rez"))

        try Self.makeArchive([
            (type: "mïsn", id: 200, name: "Plug-in mission", data: Data([2])),
            (type: "mïsn", id: 5000, name: "New plug-in mission", data: Data([3]))
        ]).write(to: subfolder.appendingPathComponent("A Plugin.rez"))

        let library = try GameDataLibrary(baseDirectory: baseDirectory, pluginsDirectory: pluginsDirectory)

        XCTAssertEqual(library.resource(ofType: "mïsn", id: 200)?.name, "Plug-in mission")
        XCTAssertEqual(library.resource(ofType: "mïsn", id: 5000)?.name, "New plug-in mission")
    }

    func testHugeEntryCountIsRejectedBeforeReservingMemory() throws {
        var archive = Self.makeArchive([(type: "mïsn", id: 200, name: "Mission", data: Data([1]))])
        // numEntries lives at byte 20.
        archive.replaceSubrange(20..<24, with: [0xF0, 0xFF, 0xFF, 0xFF])

        let url = try makeTempDirectory().appendingPathComponent("Damaged.rez")
        try archive.write(to: url)

        XCTAssertThrowsError(try RezArchive(contentsOf: url)) { error in
            XCTAssertEqual(error as? RezArchiveError, .truncated)
        }
    }

    func testHugeResourceCountIsRejected() throws {
        var archive = Self.makeArchive([(type: "mïsn", id: 200, name: "Mission", data: Data([1]))])
        // The map is the last entry: its offset is the second entry's
        // first field. The type list starts 8 bytes in, and each type's
        // resource count is 8 bytes into its 12-byte record.
        let mapOffset: Int = Int(archive[36]) | Int(archive[37]) << 8 | Int(archive[38]) << 16 | Int(archive[39]) << 24
        let countOffset: Int = mapOffset + 8 + 8
        archive.replaceSubrange(countOffset..<(countOffset + 4), with: [0x7F, 0xFF, 0xFF, 0xFF])

        let url = try makeTempDirectory().appendingPathComponent("Damaged.rez")
        try archive.write(to: url)

        XCTAssertThrowsError(try RezArchive(contentsOf: url)) { error in
            XCTAssertEqual(error as? RezArchiveError, .truncated)
        }
    }

    func testMissingPluginsFolderIsNotAnError() throws {
        let baseDirectory = try makeTempDirectory()
        try Self.makeArchive([
            (type: "mïsn", id: 200, name: "Base mission", data: Data([1]))
        ]).write(to: baseDirectory.appendingPathComponent("Data.rez"))

        let missing = baseDirectory.appendingPathComponent("No Such Folder", isDirectory: true)
        let library = try GameDataLibrary(baseDirectory: baseDirectory, pluginsDirectory: missing)

        XCTAssertEqual(library.resources.count, 1)
    }
}
