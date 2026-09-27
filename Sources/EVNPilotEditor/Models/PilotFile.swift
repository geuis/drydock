import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum PilotFileError: Error {
    case fileTooSmall
    case backupFailed
    case writeFailed
    // The file on disk no longer matches what was opened (usually the game
    // saved it), so a plain save would overwrite that newer progress.
    case changedOnDisk
}

public final class PilotFile: ObservableObject, Identifiable {
    public let url: URL
    public private(set) var originalBytes: Data
    @Published public private(set) var workingBytes: Data
    @Published public private(set) var isDirty: Bool = false

    public var id: URL { url }

    // Tracks whether this session has already made a backup of this file,
    // so `save()` only backs up once per app run rather than on every save.
    private var hasBackedUpThisSession = false

    public init(url: URL) throws {
        let data = try Data(contentsOf: url)

        // Sanity check: real pilot files are ~86KB. A tiny or empty file is
        // almost certainly not a valid save and should be refused rather than
        // silently edited/corrupted.
        guard data.count >= 100 else {
            throw PilotFileError.fileTooSmall
        }

        self.url = url
        self.originalBytes = data
        self.workingBytes = data
    }

    public func value(for field: FieldDefinition) -> PilotFieldValue? {
        try? FieldCodec.decode(field, from: workingBytes)
    }

    // Throws immediately (without mutating anything) if the field is not
    // editable. Otherwise encodes into a scratch copy of workingBytes and
    // only commits the change if encoding succeeds without throwing.
    public func setValue(_ value: PilotFieldValue, for field: FieldDefinition) throws {
        guard field.editable else {
            throw PilotFileError.writeFailed
        }

        var scratch = workingBytes
        try FieldCodec.encode(value, for: field, into: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public var isRoundTripIdentical: Bool {
        workingBytes == originalBytes
    }

    // MARK: - Convenience read accessors

    // The trailing NUL-terminated string at EOF - see PilotShipIdentity.swift
    // for the naming correction (this is the ship name, not a class name).
    public var shipName: String {
        PilotShipIdentity.decodeShipName(from: workingBytes)
    }

    // resource129's playerNickname (Pascal string) - the pilot's own
    // nickname, distinct from shipName above.
    public var nickname: String {
        PilotUniverseState.decodePlayerNickname(from: workingBytes)
    }

    // Absolute offset 6 (resource128 doc offset 0x0002). Ship ID = value + 128.
    public var shipClassIndex: Int16 {
        PilotProfile.decodeShipClassIndex(from: workingBytes)
    }

    public var isMale: Bool {
        PilotUniverseState.decodeIsMale(from: workingBytes)
    }

    public var strictPlay: Bool {
        PilotUniverseState.decodeStrictPlay(from: workingBytes)
    }

    // Last 4 bytes of resource128, absolute offset 59730.
    public var combatRating: Int32 {
        PilotProfile.decodeCombatRating(from: workingBytes)
    }

    // Absolute offset 10270.
    public var credits: Int32 {
        PilotProfile.decodeCredits(from: workingBytes)
    }

    public var missionSlots: [MissionSlot] {
        MissionSlot.decodeAll(from: workingBytes)
    }

    // Mirrors setValue(_:for:)'s pattern: encode into a scratch copy and only
    // commit if it succeeds, so a failed write never leaves workingBytes
    // partially mutated.
    public func setMissionFlag(_ flag: MissionFlagKind, to value: Bool, missionIndex: Int) throws {
        var scratch = workingBytes
        try MissionSlot.setFlag(flag, to: value, missionIndex: missionIndex, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setMissionPay(_ pay: Int32, missionIndex: Int) throws {
        var scratch = workingBytes
        try MissionSlot.setPay(pay, missionIndex: missionIndex, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    // Mirrors setMissionFlag(_:to:missionIndex:)'s pattern for the global
    // missionBit[] story/plugin flags: encode into a scratch copy and only
    // commit if it succeeds, so a failed write never leaves workingBytes
    // partially mutated.
    public func setMissionBit(_ index: Int, to value: Bool) throws {
        var scratch = workingBytes
        try MissionBits.setBit(index, to: value, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    // Several flags as one edit (marking a mission done), so views update
    // once and a bad index leaves every flag unchanged.
    public func setMissionBits(_ changes: [Int: Bool]) throws {
        guard !changes.isEmpty else { return }

        var scratch = workingBytes

        for (index, value) in changes {
            try MissionBits.setBit(index, to: value, in: &scratch)
        }

        workingBytes = scratch
        isDirty = true
    }

    // MARK: - PilotInventory

    public func setItemCount(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotInventory.setItemCount(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setWeapCount(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotInventory.setWeapCount(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setAmmo(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotInventory.setAmmo(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    // Every weapon, ammo, and outfit addition as one edit, so a failure
    // leaves the pilot unchanged.
    public func addStockLoadout(of ship: ShipDefinition) throws {
        var scratch = workingBytes
        try PilotInventory.addStockLoadout(of: ship, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    // MARK: - PilotExploration

    public func setExploration(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotExploration.setExploration(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setLegalStatus(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotExploration.setLegalStatus(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setStelDominated(_ value: Bool, at index: Int) throws {
        var scratch = workingBytes
        try PilotExploration.setStelDominated(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    // MARK: - PilotEscorts

    public func setEscortClass(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotEscorts.setEscortClass(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setFighterClass(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotEscorts.setFighterClass(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setEscortUpgrade(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotEscorts.setEscortUpgrade(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setEscortSale(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotEscorts.setEscortSale(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setEscortVoiceMode(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotEscorts.setEscortVoiceMode(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    // MARK: - PilotUniverseState

    public func setStelShipCount(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotUniverseState.setStelShipCount(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setPersonAlive(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotUniverseState.setPersonAlive(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setPersonGrudge(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotUniverseState.setPersonGrudge(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setStelAnnoyance(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotUniverseState.setStelAnnoyance(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setSeenIntroScreen(_ value: Bool) throws {
        var scratch = workingBytes
        try PilotUniverseState.setSeenIntroScreen(value, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setDisasterTime(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotUniverseState.setDisasterTime(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setDisasterStellar(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotUniverseState.setDisasterStellar(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setJunkQty(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotUniverseState.setJunkQty(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setPriceFlux(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotUniverseState.setPriceFlux(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setShipColorRed(_ value: Int16) throws {
        var scratch = workingBytes
        try PilotUniverseState.setShipColorRed(value, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setShipColorGreen(_ value: Int16) throws {
        var scratch = workingBytes
        try PilotUniverseState.setShipColorGreen(value, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setShipColorBlue(_ value: Int16) throws {
        var scratch = workingBytes
        try PilotUniverseState.setShipColorBlue(value, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setRankActive(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotUniverseState.setRankActive(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setStrictPlay(_ value: Bool) throws {
        var scratch = workingBytes
        try PilotUniverseState.setStrictPlay(value, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setIsMale(_ value: Bool) throws {
        var scratch = workingBytes
        try PilotUniverseState.setIsMale(value, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setCronDuration(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotUniverseState.setCronDuration(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setCronHoldOff(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotUniverseState.setCronHoldOff(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setReinforcements(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotUniverseState.setReinforcements(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setStelDestroyed(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotUniverseState.setStelDestroyed(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setEscortOrder(_ value: Int16, at index: Int) throws {
        var scratch = workingBytes
        try PilotUniverseState.setEscortOrder(value, at: index, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setDatePrefix(_ value: String) throws {
        var scratch = workingBytes
        try PilotUniverseState.setDatePrefix(value, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setDateSuffix(_ value: String) throws {
        var scratch = workingBytes
        try PilotUniverseState.setDateSuffix(value, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    public func setNickname(_ value: String) throws {
        var scratch = workingBytes
        try PilotUniverseState.setPlayerNickname(value, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    // MARK: - PilotShipIdentity

    // The only setter on PilotFile that resizes workingBytes - see
    // PilotShipIdentity.setShipName(_:in:) and save()'s own comments for how
    // that resize is handled safely.
    public func setShipName(_ name: String) throws {
        var scratch = workingBytes
        try PilotShipIdentity.setShipName(name, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    // MARK: - PilotProfile

    public func setShipClassIndex(_ value: Int16) throws {
        var scratch = workingBytes
        try PilotProfile.setShipClassIndex(value, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    // MARK: - MissionSlot extras

    public func setMissionTimeLeft(_ timeLeft: Int16, missionIndex: Int) throws {
        var scratch = workingBytes
        try MissionSlot.setTimeLeft(timeLeft, missionIndex: missionIndex, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    // Clears the four MissionObjectives completion flags (active/travel/
    // ship/failed) for a slot - what "remove this mission" means for the UI.
    // All four writes happen on a scratch copy first, so if any of them
    // throws (e.g. an out-of-range missionIndex), workingBytes is left
    // completely untouched rather than partially cleared.
    public func clearMissionSlot(_ missionIndex: Int) throws {
        var scratch = workingBytes
        try MissionSlot.setFlag(.isActive, to: false, missionIndex: missionIndex, in: &scratch)
        try MissionSlot.setFlag(.travelObjComplete, to: false, missionIndex: missionIndex, in: &scratch)
        try MissionSlot.setFlag(.shipObjComplete, to: false, missionIndex: missionIndex, in: &scratch)
        try MissionSlot.setFlag(.missionFailed, to: false, missionIndex: missionIndex, in: &scratch)

        workingBytes = scratch
        isDirty = true
    }

    // True when the file on disk differs from what this editor last read or
    // wrote, e.g. because the game saved the pilot in the meantime. A file
    // that can't be read counts as changed, so it is never silently replaced.
    public var hasChangedOnDisk: Bool {
        guard let diskBytes = try? Data(contentsOf: url) else { return true }

        return diskBytes != originalBytes
    }

    // Refuses with `.changedOnDisk` when the file was changed outside the
    // editor, unless `overwritingExternalChanges` is true. The backup is
    // always of the bytes actually on disk, so a newer game save that gets
    // overwritten can still be recovered from it.
    public func save(overwritingExternalChanges: Bool = false) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let diskBytes: Data? = try? Data(contentsOf: url)
        let diskChanged: Bool = diskBytes != originalBytes

        if diskChanged, !overwritingExternalChanges {
            throw PilotFileError.changedOnDisk
        }

        if !hasBackedUpThisSession || diskChanged {
            let backupURL = PilotFile.unusedBackupURL(for: url, in: directory)
            do {
                try (diskBytes ?? originalBytes).write(to: backupURL, options: .atomic)
            } catch {
                throw PilotFileError.backupFailed
            }
            hasBackedUpThisSession = true
        }

        let tempURL = directory.appendingPathComponent(url.lastPathComponent + ".tmp-\(UUID().uuidString)")

        do {
            try workingBytes.write(to: tempURL, options: .atomic)
        } catch {
            throw PilotFileError.writeFailed
        }

        do {
            _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw PilotFileError.writeFailed
        }

        originalBytes = workingBytes
        isDirty = false
    }

    // Best-effort check that isn't expected to ever throw: if the API is
    // unavailable for any reason, this reports "not running" rather than
    // blocking a save.
    public static func isGameRunning() -> Bool {
        #if canImport(AppKit)
        return NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "org.geektools.wineskin.EVNova"
        }
        #else
        return false
        #endif
    }

    private static func backupFileName(for url: URL) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        return "\(url.lastPathComponent).bak-\(timestamp)"
    }

    // Two backups in the same second would otherwise share a name, and the
    // second would replace the first.
    private static func unusedBackupURL(for url: URL, in directory: URL) -> URL {
        let baseName: String = backupFileName(for: url)
        var candidate: URL = directory.appendingPathComponent(baseName)
        var suffix: Int = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix)")
            suffix += 1
        }

        return candidate
    }
}
