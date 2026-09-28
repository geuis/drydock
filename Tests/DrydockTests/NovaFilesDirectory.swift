import Foundation
import XCTest

// Real-data tests read the developer's own EV Nova install, which can't be
// committed (it's Ambrosia's copyrighted data). Set DRYDOCK_NOVA_FILES to the
// "Nova Files" folder to run them; without it (as on CI) they are skipped,
// not failed.
extension XCTestCase {
    static let novaFilesEnvironmentKey = "DRYDOCK_NOVA_FILES"

    func novaFilesDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment[Self.novaFilesEnvironmentKey], !path.isEmpty else {
            throw XCTSkip("\(Self.novaFilesEnvironmentKey) is not set - skipping real-data test.")
        }

        let directory = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw XCTSkip("\(Self.novaFilesEnvironmentKey) points at \(directory.path), which is not a folder - skipping real-data test.")
        }

        return directory
    }
}
