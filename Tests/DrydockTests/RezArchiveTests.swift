import XCTest
@testable import Drydock

// These tests parse the real EV Nova game data files installed on this
// machine (outside the repo, at ~/Desktop/EV Nova/Nova Files/). They are the
// only real-world check we have for RezArchive's BRGR parsing, since no
// synthetic fixture can substitute for the actual file layout. If that game
// install isn't present (a different machine, CI, etc.) every test here
// skips gracefully via XCTSkip rather than failing.
final class RezArchiveTests: XCTestCase {
    private func novaFilesDirectory() throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("EV Nova", isDirectory: true)
            .appendingPathComponent("Nova Files", isDirectory: true)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw XCTSkip("EV Nova game files not found at \(directory.path) - skipping real-file verification.")
        }

        return directory
    }

    private func novaDataFileURLs() throws -> [URL] {
        let directory = try novaFilesDirectory()
        let urls = (1...6).map { directory.appendingPathComponent("Nova Data \($0).rez") }

        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw XCTSkip("Expected file not found: \(url.path) - skipping real-file verification.")
            }
        }

        return urls
    }

    // Confirms every Nova Data N.rez file parses without throwing, and that
    // each yields a plausible (non-trivial) number of resources.
    func testParsesAllNovaDataFiles() throws {
        let urls = try novaDataFileURLs()

        for url in urls {
            let archive = try RezArchive(contentsOf: url)
            XCTAssertGreaterThan(archive.resources.count, 0, "\(url.lastPathComponent) produced no resources")
        }
    }

    // Loads Nova Data 1-6.rez through GameDataLibrary and confirms the merge
    // finds ship, outfit, weapon, and mission resources with plausible IDs
    // (classic Mac resource IDs for game content start at 128), and that
    // ship names decode as readable text rather than garbage - the strongest
    // signal that the MacRoman decoding and fixed-width name field skip are
    // both correct.
    func testFindsExpectedResourceTypesWithPlausibleIdsAndNames() throws {
        let directory = try novaFilesDirectory()
        _ = try novaDataFileURLs() // ensures skip if Data files aren't present

        let library = try GameDataLibrary(contentsOfDirectory: directory)

        // Only look at the Nova Data files' contribution for this assertion,
        // since GameDataLibrary loads every .rez in the directory (including
        // graphics/sound/titles, which may or may not share this resource
        // layout) - Data files are where ship/outfit/weapon/mission
        // definitions are expected to live per the Nova Bible.
        let expectedTypes = ["shïp", "oütf", "wëap", "mïsn"]

        for type in expectedTypes {
            let matches = library.resources(ofType: type)
            XCTAssertFalse(matches.isEmpty, "Expected to find resources of type '\(type)'")

            for resource in matches {
                XCTAssertGreaterThanOrEqual(resource.id, 128, "\(type) resource id \(resource.id) is below the expected classic-Mac floor of 128")
            }
        }

        let ships = library.resources(ofType: "shïp")
        let sampleNames = ships.prefix(10).map { $0.name }

        print("Sample ship names (\(sampleNames.count) of \(ships.count) total):")
        for name in sampleNames {
            print("  - \(name)")
        }

        // Plausible-name check: real ship class names are short readable
        // strings (letters, spaces, punctuation) - not empty, and not raw
        // control-character/garbage. This is a loose sanity check, not an
        // exact match, since actual names are scenario-specific content.
        for name in sampleNames {
            XCTAssertFalse(name.isEmpty, "Ship resource name should not be empty")
            let hasLetter = name.contains { $0.isLetter }
            XCTAssertTrue(hasLetter, "Ship resource name '\(name)' doesn't look like readable text")
        }

        print("Resource counts - ships: \(ships.count), outfits: \(library.resources(ofType: "oütf").count), weapons: \(library.resources(ofType: "wëap").count), missions: \(library.resources(ofType: "mïsn").count)")

        if !library.failedArchives.isEmpty {
            print("Archives that failed to parse (expected for non-BRGR-map files like graphics/sound):")
            for failure in library.failedArchives {
                print("  - \(failure.url.lastPathComponent): \(failure.error)")
            }
        }
    }

    // Loose cross-check against the Nova Bible's documented maximums (Max
    // Ship Classes 768, Max Weapon Types 256, Max Outfit Item Types 512, Max
    // Missions 1000). A single scenario's actual counts should be well below
    // these ceilings - this just guards against grossly over-counting due to
    // a parsing bug (e.g. misaligned cursor producing bogus extra entries).
    func testResourceCountsAreWithinNovaBibleCeilings() throws {
        let directory = try novaFilesDirectory()
        _ = try novaDataFileURLs()

        let library = try GameDataLibrary(contentsOfDirectory: directory)

        XCTAssertLessThanOrEqual(library.resources(ofType: "shïp").count, 768)
        XCTAssertLessThanOrEqual(library.resources(ofType: "wëap").count, 256)
        XCTAssertLessThanOrEqual(library.resources(ofType: "oütf").count, 512)
        XCTAssertLessThanOrEqual(library.resources(ofType: "mïsn").count, 1000)
    }

    // Nova Ships N.rez files parse under the same BRGR layout as the Data
    // files, but empirically hold mostly graphics/animation resources
    // (e.g. "shän" ship animations, "PICT" images, "rlëD") rather than the
    // "shïp"/"oütf"/"wëap"/"mïsn" definition resources themselves - this
    // just confirms that finding empirically rather than assuming it.
    func testParsesNovaShipsFilesAndReportsResourceTypeBreakdown() throws {
        let directory = try novaFilesDirectory()
        let shipsFileURLs = (1...8).map { directory.appendingPathComponent("Nova Ships \($0).rez") }

        for url in shipsFileURLs {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw XCTSkip("Expected file not found: \(url.path) - skipping Nova Ships verification.")
            }
        }

        var typeCounts: [String: Int] = [:]

        for url in shipsFileURLs {
            let archive = try RezArchive(contentsOf: url)
            XCTAssertGreaterThan(archive.resources.count, 0, "\(url.lastPathComponent) produced no resources")

            for resource in archive.resources {
                typeCounts[resource.type, default: 0] += 1
            }
        }

        print("Nova Ships 1-8.rez combined resource type breakdown:")
        for (type, count) in typeCounts.sorted(by: { $0.value > $1.value }) {
            print("  - \(type): \(count)")
        }
    }
}
