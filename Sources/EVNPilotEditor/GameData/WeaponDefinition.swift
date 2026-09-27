import Foundation

// Decoded EV Nova "wëap" (weapon) resource - defines a weapon's combat
// behavior. A weapon is bought/carried via a matching oütf item whose
// ModType is 1 ("a weapon", ModVal = this resource's id), or used as ammo
// when an oütf item's ModType is 3. Field order and meaning are documented
// in the Nova Bible ("The wëap resource" section, lines 3135-3518 of the
// converted text). The bible does not state exact byte offsets or widths -
// those were derived empirically against all 81 real wëap resources found
// in the installed game data, cross-checked field by field against what
// each weapon's name/role implies. See "Field confidence" below.
//
// The strongest confirmations found for the fields decoded in this pass:
// - Seeker (offset 30) is 0 for every non-guided weapon and only nonzero
//   for Guidance==1 (homing) weapons - exactly matches the bible's "ignored
//   if the weapon is not a guided weapon" note.
// - PartColor/BeamColor/CoronaColor/HitPartColor/IonizeColor decode to
//   thematically obvious colors: Polaron torpedoes decode a magenta/purple
//   particle color, "Solar Lance" a yellow beam, "Thunderhead Lance" a
//   green beam, railguns a consistent dark-blue muzzle-particle color
//   shared across all three calibers, the seasonal "Flower/Summer/Autumn/
//   Winter" weapon family shares one pale-pink hit-particle color, and
//   "Hellhound Missile" decodes a fiery orange-red hit color.
// - SubType (offset 64) resolves to a real weapon resource ID that matches
//   the submunition weapon's own name: "Nanites" splits into more Nanites
//   (self-referencing), "Polaron Multi-Torp." splits into plain
//   "Polaron Torp." - exactly what "multi" implies.
// - Falloff (offset 52) is always within the bible's documented 2-16 range
//   whenever nonzero, across every one of the 14 weapons that set it.
// - ExitType (offset 88) is 3 ("BeamPosX/Y") for every single beam-type
//   weapon (Guidance 0 or 3) and only those - no other Guidance value ever
//   uses ExitType 3.
// - JamVuln1-4 (offsets 94-100), Durability (104) and GuidedTurn (106) are
//   nonzero only for Guidance==1 (homing) weapons (Raven Rocket/Turret are
//   the only exceptions for Durability) - matches the bible's "ignored if
//   not a guided weapon" notes for all three.
// - MaxAmmo (offset 108) is nonzero only for fighter bays (Guidance==99),
//   and its value matches the well-known number of fighters each bay type
//   carries (e.g. Viper Bay == 4).
// - LiDensity/LiAmplitude (offsets 110/112) are nonzero only for the
//   "Wraith Graviton Beam" family (the game's canonical lightning beam),
//   "Winter Tempest", "TripHammer" and "Polaron Cannon", and scale up
//   through the Wraith Beam's Child/Youth/Adult tiers exactly as a
//   zig-zag-density field would.
// - Flags2 bit 0x0200 ("weapon uses the ship's weapon sprite") is set on
//   turreted weapons specifically, and Flags2 bit 0x1000 ("can disable but
//   not destroy") plus 0x0200 together on "Ion Cannon" match its
//   well-known disable-not-destroy gameplay trait exactly.
//
// One documented field, Recoil, could not be confidently placed: every
// other documented field maps to exactly one offset in exact bible order
// with no gaps, except for an always-zero 2-byte span at offset 86-87
// (between HitPartColor and ExitType) that doesn't correspond to any
// field at that position in the bible's ordering. It's left undecoded
// (see Layout.reservedOffset) rather than guessed, since none of the 81
// real resources set it to anything but zero, giving no way to confirm
// its meaning empirically.
//
// Every wëap resource in the real game data is exactly 134 bytes. Bytes
// 118-133 (16 bytes) are confirmed always zero across all 81 real
// resources and are not decoded - most likely reserved/padding space.
// This resource has no trailing string fields; the weapon's display name
// comes entirely from the resource's own name (GameResource.name).
public struct WeaponDefinition: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String

    public let reload: Int16
    public let count: Int16
    public let massDamage: Int16
    public let energyDamage: Int16
    public let guidance: Int16
    public let speed: Int16
    public let ammoType: Int16

    public let graphic: Int16
    public let inaccuracy: Int16
    public let sound: Int16

    public let impact: Int16
    public let explodType: Int16
    public let proxRadius: Int16
    public let blastRadius: Int16

    // MARK: - Behavior flags & guided-weapon fields

    public let flags: Int16
    public let seeker: Int16
    public let smokeSet: Int16
    public let decay: Int16

    // MARK: - Particle trail

    public let particles: Int16
    public let partVel: Int16
    public let partLifeMin: Int16
    public let partLifeMax: Int16
    public let partColor: RGBColor

    // MARK: - Beam presentation

    public let beamLength: Int16
    public let beamWidth: Int16
    public let falloff: Int16
    public let beamColor: RGBColor
    public let coronaColor: RGBColor

    // MARK: - Submunitions

    public let subCount: Int16
    public let subType: Int16
    public let subTheta: Int16
    public let subLimit: Int16
    public let proxSafety: Int16

    // MARK: - More flags & hit effects

    public let flags2: Int16
    public let ionization: Int16
    public let hitParticles: Int16
    public let hitPartLife: Int16
    public let hitPartVel: Int16
    public let hitPartColor: RGBColor

    // MARK: - Firing mechanics

    public let exitType: Int16
    public let burstCount: Int16
    public let burstReload: Int16

    // MARK: - Jamming vulnerability (guided weapons only)

    public let jamVuln1: Int16
    public let jamVuln2: Int16
    public let jamVuln3: Int16
    public let jamVuln4: Int16

    // MARK: - Advanced combat fields

    public let flags3: Int16
    public let durability: Int16
    public let guidedTurn: Int16
    public let maxAmmo: Int16

    // MARK: - Lightning beam & ionization

    public let liDensity: Int16
    public let liAmplitude: Int16
    public let ionizeColor: RGBColor

    // MARK: - RGBColor

    // A resource-packed 24-bit color (documented as "00RRGGBB", i.e. a
    // 4-byte big-endian field whose top byte is always zero). Used by
    // PartColor/BeamColor/CoronaColor/HitPartColor/IonizeColor.
    public struct RGBColor: Equatable, Sendable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8

        init(packed: UInt32) {
            red = UInt8((packed >> 16) & 0xFF)
            green = UInt8((packed >> 8) & 0xFF)
            blue = UInt8(packed & 0xFF)
        }

        // Swatch-friendly "#RRGGBB" form for display in the catalog UI.
        public var hexString: String {
            String(format: "#%02X%02X%02X", red, green, blue)
        }

        public var isBlack: Bool {
            red == 0 && green == 0 && blue == 0
        }
    }

    // MARK: - Guidance lookup

    // The Nova Bible's documented Guidance mode table (wëap section). Not
    // every value in the source range is used by real data; unused ones are
    // simply absent here rather than guessed at.
    public static let guidanceDescriptions: [Int16: String] = [
        -1: "Unguided projectile",
        0: "Beam weapon",
        1: "Homing weapon",
        3: "Turreted beam",
        4: "Turreted, unguided projectile",
        5: "Freefall bomb",
        6: "Freeflight rocket",
        7: "Front-quadrant turret",
        8: "Rear-quadrant turret",
        9: "Point defense turret",
        10: "Point defense beam",
        99: "Carried ship (fighter bay)"
    ]

    public static func guidanceDescription(for guidance: Int16) -> String {
        guidanceDescriptions[guidance] ?? "Unknown (\(guidance))"
    }

    // True for the two Guidance values whose fields mean something
    // different (Count/Impact/ProxRadius/BlastRadius all change meaning
    // per the bible's "Please note..." section) and whose BeamLength/
    // BeamWidth/Falloff/BeamColor/CoronaColor fields are the ones that
    // actually apply.
    public static func isBeam(guidance: Int16) -> Bool {
        guidance == 0 || guidance == 3
    }

    // MARK: - Bitfield lookups

    // Flags (offset 28). Bit -> short description, in the bible's own
    // order. Not every bit is necessarily used by any given real weapon;
    // activeFlags(for:) below reports which are actually set.
    public static let flagDescriptions: [(bit: Int16, description: String)] = [
        (0x0001, "Spins graphic continuously"),
        (0x0002, "Fired by second trigger"),
        (0x0004, "Cycling: always starts on first frame"),
        (0x0008, "Guided: won't fire at fast ships"),
        (0x0010, "Sound is looped"),
        (0x0020, "Passes through shields"),
        (0x0040, "Multiple weapons fire simultaneously"),
        (0x0080, "Can't be targeted by point defense"),
        (0x0100, "Blast doesn't hurt the player"),
        (0x0200, "Generates small smoke"),
        (0x0400, "Generates big smoke"),
        (0x0800, "Smoke trail is more persistent"),
        (0x1000, "Turreted: blind spot to the front"),
        (0x2000, "Turreted: blind spot to the sides"),
        (0x4000, "Turreted: blind spot to the rear"),
        (-0x8000, "Detonates at the end of its lifespan")
    ]

    // Seeker (offset 30) - guided-weapon-only behavior flags.
    public static let seekerDescriptions: [(bit: Int16, description: String)] = [
        (0x0001, "Passes over asteroids"),
        (0x0002, "Decoyed by asteroids"),
        (0x0008, "Confused by sensor interference"),
        (0x0010, "Turns away if jammed"),
        (0x0020, "Can't fire if ship is ionized"),
        (0x4000, "Loses lock if target not directly ahead"),
        (-0x8000, "May attack parent ship if jammed")
    ]

    // Flags2 (offset 72).
    public static let flags2Descriptions: [(bit: Int16, description: String)] = [
        (0x0001, "Cycling: hold first frame until ProxSafety expires"),
        (0x0002, "Cycling: stops on the last frame"),
        (0x0004, "Proximity detonator ignores asteroids"),
        (0x0008, "Proximity detonator triggered by non-target ships"),
        (0x0010, "Submunitions fire toward nearest valid target"),
        (0x0020, "Doesn't launch submunitions when the shot expires"),
        (0x0040, "Ammo quantity hidden from status display"),
        (0x0080, "Requires a ship of this ship's KeyCarried type aboard"),
        (0x0100, "AI ships won't use this weapon"),
        (0x0200, "Uses the ship's weapon sprite"),
        (0x0400, "Planet-type weapon"),
        (0x0800, "Hidden/unselectable when out of ammo"),
        (0x1000, "Can disable but not destroy"),
        (0x2000, "Beam displays underneath ships"),
        (0x4000, "Can be fired while cloaked"),
        (-0x8000, "Does x10 mass damage to asteroids")
    ]

    // Flags3 (offset 102).
    public static let flags3Descriptions: [(bit: Int16, description: String)] = [
        (0x0001, "Only uses ammo at the end of a burst cycle"),
        (0x0002, "Shots are translucent"),
        (0x0004, "Can't refire until the previous shot expires/hits"),
        (0x0010, "Fires from the exit point closest to the target"),
        (0x0020, "Exclusive: blocks other weapons while firing/reloading")
    ]

    private static func activeDescriptions(
        for value: Int16,
        in table: [(bit: Int16, description: String)]
    ) -> [String] {
        let raw = UInt16(bitPattern: value)
        return table
            .filter { UInt16(bitPattern: $0.bit) & raw != 0 }
            .map(\.description)
    }

    public static func activeFlags(for flags: Int16) -> [String] {
        activeDescriptions(for: flags, in: flagDescriptions)
    }

    public static func activeSeekerBehaviors(for seeker: Int16) -> [String] {
        activeDescriptions(for: seeker, in: seekerDescriptions)
    }

    public static func activeFlags2(for flags2: Int16) -> [String] {
        activeDescriptions(for: flags2, in: flags2Descriptions)
    }

    public static func activeFlags3(for flags3: Int16) -> [String] {
        activeDescriptions(for: flags3, in: flags3Descriptions)
    }

    // ExitType (offset 88).
    public static let exitTypeDescriptions: [Int16: String] = [
        -1: "Ignored (fires from ship center)",
        0: "GunPosX/Y",
        1: "TurretPosX/Y",
        2: "GuidedPosX/Y",
        3: "BeamPosX/Y"
    ]

    public static func exitTypeDescription(for exitType: Int16) -> String {
        exitTypeDescriptions[exitType] ?? "Unknown (\(exitType))"
    }

    // Whether this weapon has a lightning-style beam (per the bible: a
    // LiDensity greater than zero turns a normal beam into a lightning
    // beam, which ignores CoronaColor/Falloff and only uses BeamColor).
    public var isLightningBeam: Bool {
        liDensity > 0
    }

    // The four JamVuln fields as one array, for iterating in the UI.
    public var jamVulnerabilities: [Int16] {
        [jamVuln1, jamVuln2, jamVuln3, jamVuln4]
    }

    // MARK: - Layout

    enum Layout {
        static let reloadOffset = 0
        static let countOffset = 2
        static let massDamageOffset = 4
        static let energyDamageOffset = 6
        static let guidanceOffset = 8
        static let speedOffset = 10
        static let ammoTypeOffset = 12

        static let graphicOffset = 14
        static let inaccuracyOffset = 16
        static let soundOffset = 18

        static let impactOffset = 20
        static let explodTypeOffset = 22
        static let proxRadiusOffset = 24
        static let blastRadiusOffset = 26

        static let flagsOffset = 28
        static let seekerOffset = 30
        static let smokeSetOffset = 32
        static let decayOffset = 34

        static let particlesOffset = 36
        static let partVelOffset = 38
        static let partLifeMinOffset = 40
        static let partLifeMaxOffset = 42
        static let partColorOffset = 44 // 4-byte field, occupies 44-47

        static let beamLengthOffset = 48
        static let beamWidthOffset = 50
        static let falloffOffset = 52
        static let beamColorOffset = 54 // 4-byte field, occupies 54-57
        static let coronaColorOffset = 58 // 4-byte field, occupies 58-61

        static let subCountOffset = 62
        static let subTypeOffset = 64
        static let subThetaOffset = 66
        static let subLimitOffset = 68
        static let proxSafetyOffset = 70

        static let flags2Offset = 72
        static let ionizationOffset = 74
        static let hitParticlesOffset = 76
        static let hitPartLifeOffset = 78
        static let hitPartVelOffset = 80
        static let hitPartColorOffset = 82 // 4-byte field, occupies 82-85

        // Always zero across all 81 real wëap resources found. Doesn't
        // correspond to any field in the bible's documented order at this
        // position - the one documented field that couldn't be placed
        // (Recoil) would belong much later, between MaxAmmo and LiDensity,
        // where the data leaves no room for it. Left undecoded rather than
        // guessed; see the file header comment.
        static let reservedOffset = 86

        static let exitTypeOffset = 88
        static let burstCountOffset = 90
        static let burstReloadOffset = 92

        static let jamVuln1Offset = 94
        static let jamVuln2Offset = 96
        static let jamVuln3Offset = 98
        static let jamVuln4Offset = 100

        static let flags3Offset = 102
        static let durabilityOffset = 104
        static let guidedTurnOffset = 106
        static let maxAmmoOffset = 108

        static let liDensityOffset = 110
        static let liAmplitudeOffset = 112
        static let ionizeColorOffset = 114 // 4-byte field, occupies 114-117

        // Confirmed fixed size for every wëap resource found in the real
        // game data (81 resources, all exactly this size). Bytes 118-133
        // are confirmed always zero and are not decoded.
        static let expectedSize = 134
    }

    // MARK: - Decoding

    public static func decodeAll(from library: GameDataLibrary) -> [WeaponDefinition] {
        library.resources(ofType: "wëap").compactMap { decode($0) }
    }

    // Never throws out to the caller - a malformed or unexpectedly-shaped
    // resource is simply skipped rather than crashing the catalog, matching
    // this codebase's defensive-decoding convention (see MissionSlot).
    private static func decode(_ resource: GameResource) -> WeaponDefinition? {
        let reader = ByteReader(resource.data)

        do {
            let reload = try reader.int16(at: Layout.reloadOffset, byteOrder: .big)
            let count = try reader.int16(at: Layout.countOffset, byteOrder: .big)
            let massDamage = try reader.int16(at: Layout.massDamageOffset, byteOrder: .big)
            let energyDamage = try reader.int16(at: Layout.energyDamageOffset, byteOrder: .big)
            let guidance = try reader.int16(at: Layout.guidanceOffset, byteOrder: .big)
            let speed = try reader.int16(at: Layout.speedOffset, byteOrder: .big)
            let ammoType = try reader.int16(at: Layout.ammoTypeOffset, byteOrder: .big)

            let graphic = try reader.int16(at: Layout.graphicOffset, byteOrder: .big)
            let inaccuracy = try reader.int16(at: Layout.inaccuracyOffset, byteOrder: .big)
            let sound = try reader.int16(at: Layout.soundOffset, byteOrder: .big)

            let impact = try reader.int16(at: Layout.impactOffset, byteOrder: .big)
            let explodType = try reader.int16(at: Layout.explodTypeOffset, byteOrder: .big)
            let proxRadius = try reader.int16(at: Layout.proxRadiusOffset, byteOrder: .big)
            let blastRadius = try reader.int16(at: Layout.blastRadiusOffset, byteOrder: .big)

            let flags = try reader.int16(at: Layout.flagsOffset, byteOrder: .big)
            let seeker = try reader.int16(at: Layout.seekerOffset, byteOrder: .big)
            let smokeSet = try reader.int16(at: Layout.smokeSetOffset, byteOrder: .big)
            let decay = try reader.int16(at: Layout.decayOffset, byteOrder: .big)

            let particles = try reader.int16(at: Layout.particlesOffset, byteOrder: .big)
            let partVel = try reader.int16(at: Layout.partVelOffset, byteOrder: .big)
            let partLifeMin = try reader.int16(at: Layout.partLifeMinOffset, byteOrder: .big)
            let partLifeMax = try reader.int16(at: Layout.partLifeMaxOffset, byteOrder: .big)
            let partColor = RGBColor(packed: try reader.uint32(at: Layout.partColorOffset, byteOrder: .big))

            let beamLength = try reader.int16(at: Layout.beamLengthOffset, byteOrder: .big)
            let beamWidth = try reader.int16(at: Layout.beamWidthOffset, byteOrder: .big)
            let falloff = try reader.int16(at: Layout.falloffOffset, byteOrder: .big)
            let beamColor = RGBColor(packed: try reader.uint32(at: Layout.beamColorOffset, byteOrder: .big))
            let coronaColor = RGBColor(packed: try reader.uint32(at: Layout.coronaColorOffset, byteOrder: .big))

            let subCount = try reader.int16(at: Layout.subCountOffset, byteOrder: .big)
            let subType = try reader.int16(at: Layout.subTypeOffset, byteOrder: .big)
            let subTheta = try reader.int16(at: Layout.subThetaOffset, byteOrder: .big)
            let subLimit = try reader.int16(at: Layout.subLimitOffset, byteOrder: .big)
            let proxSafety = try reader.int16(at: Layout.proxSafetyOffset, byteOrder: .big)

            let flags2 = try reader.int16(at: Layout.flags2Offset, byteOrder: .big)
            let ionization = try reader.int16(at: Layout.ionizationOffset, byteOrder: .big)
            let hitParticles = try reader.int16(at: Layout.hitParticlesOffset, byteOrder: .big)
            let hitPartLife = try reader.int16(at: Layout.hitPartLifeOffset, byteOrder: .big)
            let hitPartVel = try reader.int16(at: Layout.hitPartVelOffset, byteOrder: .big)
            let hitPartColor = RGBColor(packed: try reader.uint32(at: Layout.hitPartColorOffset, byteOrder: .big))

            let exitType = try reader.int16(at: Layout.exitTypeOffset, byteOrder: .big)
            let burstCount = try reader.int16(at: Layout.burstCountOffset, byteOrder: .big)
            let burstReload = try reader.int16(at: Layout.burstReloadOffset, byteOrder: .big)

            let jamVuln1 = try reader.int16(at: Layout.jamVuln1Offset, byteOrder: .big)
            let jamVuln2 = try reader.int16(at: Layout.jamVuln2Offset, byteOrder: .big)
            let jamVuln3 = try reader.int16(at: Layout.jamVuln3Offset, byteOrder: .big)
            let jamVuln4 = try reader.int16(at: Layout.jamVuln4Offset, byteOrder: .big)

            let flags3 = try reader.int16(at: Layout.flags3Offset, byteOrder: .big)
            let durability = try reader.int16(at: Layout.durabilityOffset, byteOrder: .big)
            let guidedTurn = try reader.int16(at: Layout.guidedTurnOffset, byteOrder: .big)
            let maxAmmo = try reader.int16(at: Layout.maxAmmoOffset, byteOrder: .big)

            let liDensity = try reader.int16(at: Layout.liDensityOffset, byteOrder: .big)
            let liAmplitude = try reader.int16(at: Layout.liAmplitudeOffset, byteOrder: .big)
            let ionizeColor = RGBColor(packed: try reader.uint32(at: Layout.ionizeColorOffset, byteOrder: .big))

            return WeaponDefinition(
                id: resource.id,
                name: resource.name,
                reload: reload,
                count: count,
                massDamage: massDamage,
                energyDamage: energyDamage,
                guidance: guidance,
                speed: speed,
                ammoType: ammoType,
                graphic: graphic,
                inaccuracy: inaccuracy,
                sound: sound,
                impact: impact,
                explodType: explodType,
                proxRadius: proxRadius,
                blastRadius: blastRadius,
                flags: flags,
                seeker: seeker,
                smokeSet: smokeSet,
                decay: decay,
                particles: particles,
                partVel: partVel,
                partLifeMin: partLifeMin,
                partLifeMax: partLifeMax,
                partColor: partColor,
                beamLength: beamLength,
                beamWidth: beamWidth,
                falloff: falloff,
                beamColor: beamColor,
                coronaColor: coronaColor,
                subCount: subCount,
                subType: subType,
                subTheta: subTheta,
                subLimit: subLimit,
                proxSafety: proxSafety,
                flags2: flags2,
                ionization: ionization,
                hitParticles: hitParticles,
                hitPartLife: hitPartLife,
                hitPartVel: hitPartVel,
                hitPartColor: hitPartColor,
                exitType: exitType,
                burstCount: burstCount,
                burstReload: burstReload,
                jamVuln1: jamVuln1,
                jamVuln2: jamVuln2,
                jamVuln3: jamVuln3,
                jamVuln4: jamVuln4,
                flags3: flags3,
                durability: durability,
                guidedTurn: guidedTurn,
                maxAmmo: maxAmmo,
                liDensity: liDensity,
                liAmplitude: liAmplitude,
                ionizeColor: ionizeColor
            )
        } catch {
            return nil
        }
    }
}
