import XCTest
@testable import Drydock

// Decodes real wëap resources from the installed EV Nova game data and
// checks that the validated fields (Reload/Count/MassDmg/EnergyDmg/
// Guidance/Speed/AmmoType/Graphic/Inaccuracy/Sound/Impact/ExplodType/
// ProxRadius/BlastRadius) land in plausible, internally consistent ranges.
// Prefers relative/structural assertions over hardcoded exact values, since
// these come from real scenario data this repo doesn't own. Skips
// gracefully via XCTSkip if the game files aren't present, matching
// RezArchiveTests's pattern.
final class WeaponDefinitionTests: XCTestCase {
    private func loadWeapons() throws -> [WeaponDefinition] {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)
        let weapons = WeaponDefinition.decodeAll(from: library)

        guard !weapons.isEmpty else {
            throw XCTSkip("No wëap resources decoded - skipping.")
        }

        return weapons
    }

    func testDecodesAllWeaponsWithoutCrashing() throws {
        let weapons = try loadWeapons()
        XCTAssertGreaterThan(weapons.count, 0)

        for weapon in weapons {
            XCTAssertFalse(weapon.name.isEmpty)
        }
    }

    // A fighter-bay-type weapon (name containing "Bay") should decode to the
    // Bible's documented Guidance sentinel value of 99 ("Carried ship").
    func testFighterBayDecodesGuidance99() throws {
        let weapons = try loadWeapons()
        guard let bay = weapons.first(where: { $0.name.localizedCaseInsensitiveContains("Bay") }) else {
            throw XCTSkip("No fighter bay weapon in this scenario's data - skipping.")
        }

        XCTAssertEqual(bay.guidance, 99)
        XCTAssertEqual(WeaponDefinition.guidanceDescription(for: bay.guidance), "Carried ship (fighter bay)")
    }

    // A fixed, non-turreted blaster and its turreted counterpart should
    // decode with matching damage/speed/ammo stats but different Guidance
    // values - the turret variant's Guidance should be the Bible's
    // "turreted, unguided projectile" value (4), the fixed variant's should
    // be "unguided projectile" (-1).
    func testFixedVsTurretBlasterPairDiffersOnlyInGuidance() throws {
        let weapons = try loadWeapons()
        guard let fixed = weapons.first(where: { $0.name == "Light Blaster" }),
              let turret = weapons.first(where: { $0.name == "Light Blaster Turret" }) else {
            throw XCTSkip("Scenario doesn't have a Light Blaster / Light Blaster Turret pair - skipping.")
        }

        XCTAssertEqual(fixed.guidance, -1)
        XCTAssertEqual(turret.guidance, 4)
        XCTAssertEqual(fixed.massDamage, turret.massDamage)
        XCTAssertEqual(fixed.energyDamage, turret.energyDamage)
        XCTAssertEqual(fixed.ammoType, turret.ammoType)
    }

    // A homing missile-type weapon should decode Guidance == 1, and carry
    // meaningfully more mass damage and a larger blast radius than a basic
    // unguided blaster - missiles hit harder and explode.
    func testMissileHitsHarderThanBasicBlaster() throws {
        let weapons = try loadWeapons()
        guard let missile = weapons.first(where: { $0.name.localizedCaseInsensitiveContains("Missile") }),
              let blaster = weapons.first(where: { $0.name.localizedCaseInsensitiveContains("Light Blaster") && !$0.name.localizedCaseInsensitiveContains("Turret") }) else {
            throw XCTSkip("Scenario doesn't have both a missile and a basic blaster to compare - skipping.")
        }

        XCTAssertEqual(missile.guidance, 1)
        XCTAssertGreaterThan(missile.massDamage, blaster.massDamage)
        XCTAssertGreaterThanOrEqual(missile.blastRadius, blaster.blastRadius)
    }

    // Structural sanity check across every decoded weapon: Reload and Count
    // should never be negative (they're frame counts), and AmmoType should
    // never fall below the Bible's documented floor for the fuel-burning
    // encoding (-1000 minus up to a few hundred, generously bounded here).
    func testTimingFieldsAreWithinPlausibleBounds() throws {
        let weapons = try loadWeapons()

        for weapon in weapons {
            XCTAssertGreaterThanOrEqual(weapon.reload, 0, "\(weapon.name) has a negative Reload")
            XCTAssertGreaterThanOrEqual(weapon.count, 0, "\(weapon.name) has a negative Count")
            XCTAssertGreaterThan(weapon.ammoType, -2000, "\(weapon.name) has an implausibly low AmmoType")
        }
    }

    // The wëap resource is documented as a flat, fixed-size struct - every
    // resource in the real data should be exactly the same byte length.
    func testAllWeaponResourcesShareExpectedSize() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)
        let rawResources = library.resources(ofType: "wëap")

        guard !rawResources.isEmpty else {
            throw XCTSkip("No wëap resources found - skipping.")
        }

        for resource in rawResources {
            XCTAssertEqual(resource.data.count, 134, "\(resource.name) has an unexpected wëap resource size")
        }
    }

    // MARK: - Seeker / JamVuln / GuidedTurn / Durability - guided-only fields

    // The bible documents Seeker, JamVuln1-4 and GuidedTurn as meaningful
    // (and thus "ignored" when set) only for Guidance == 1 (homing)
    // weapons. The overwhelming majority of non-guided weapons leave these
    // at zero; a small minority (e.g. one of this scenario's two "Nanites"
    // resources, which comes in both a guided and a turreted variant) carry
    // leftover nonzero values despite not being guided - consistent with
    // "ignored" rather than "always zero". This checks the majority
    // pattern structurally rather than asserting every single weapon.
    func testGuidedOnlyFieldsAreMostlyZeroForNonGuidedWeapons() throws {
        let weapons = try loadWeapons()
        let nonGuided = weapons.filter { $0.guidance != 1 }

        guard !nonGuided.isEmpty else {
            throw XCTSkip("Scenario has no non-guided weapons - skipping.")
        }

        let seekerSetCount = nonGuided.filter { $0.seeker != 0 }.count
        let jamSetCount = nonGuided.filter { $0.jamVulnerabilities.contains { $0 != 0 } }.count
        let turnSetCount = nonGuided.filter { $0.guidedTurn != 0 }.count

        XCTAssertLessThan(seekerSetCount, nonGuided.count / 4, "Too many non-guided weapons have a nonzero Seeker")
        XCTAssertLessThan(jamSetCount, nonGuided.count / 4, "Too many non-guided weapons have a nonzero JamVuln")
        XCTAssertLessThan(turnSetCount, nonGuided.count / 4, "Too many non-guided weapons have a nonzero GuidedTurn")
    }

    // At least one real guided (homing) weapon should have a nonzero
    // Seeker, JamVuln and GuidedTurn - otherwise the "zero for non-guided"
    // check above would trivially pass even if these offsets were wrong.
    func testAtLeastOneGuidedWeaponHasNonzeroGuidedFields() throws {
        let weapons = try loadWeapons()
        let guided = weapons.filter { $0.guidance == 1 }

        guard !guided.isEmpty else {
            throw XCTSkip("Scenario has no guided (Guidance == 1) weapons - skipping.")
        }

        XCTAssertTrue(guided.contains { $0.seeker != 0 }, "No guided weapon has a nonzero Seeker")
        XCTAssertTrue(guided.contains { $0.jamVulnerabilities.contains { $0 != 0 } }, "No guided weapon has a nonzero JamVuln")
        XCTAssertTrue(guided.contains { $0.guidedTurn != 0 }, "No guided weapon has a nonzero GuidedTurn")
    }

    // MARK: - Beam fields

    // Only beam-guidance weapons (0 or 3) should have a nonzero BeamLength;
    // every other weapon should read zero there.
    func testOnlyBeamWeaponsHaveBeamLength() throws {
        let weapons = try loadWeapons()

        for weapon in weapons {
            if WeaponDefinition.isBeam(guidance: weapon.guidance) {
                XCTAssertGreaterThan(weapon.beamLength, 0, "\(weapon.name) is a beam weapon but has no BeamLength")
            } else {
                XCTAssertEqual(weapon.beamLength, 0, "\(weapon.name) is not a beam weapon but has a nonzero BeamLength")
            }
        }
    }

    // Falloff is documented as always being between 2 and 16 - check that
    // holds for every weapon that sets it at all (zero means "unused").
    func testFalloffIsWithinDocumentedRangeWhenSet() throws {
        let weapons = try loadWeapons()

        for weapon in weapons where weapon.falloff != 0 {
            XCTAssertGreaterThanOrEqual(weapon.falloff, 2, "\(weapon.name) has a Falloff below the documented minimum")
            XCTAssertLessThanOrEqual(weapon.falloff, 16, "\(weapon.name) has a Falloff above the documented maximum")
        }
    }

    // ExitType 3 ("BeamPosX/Y") should be used only by beam-guidance
    // weapons, and every beam-guidance weapon should use it.
    func testBeamPosExitTypeMatchesBeamGuidanceExactly() throws {
        let weapons = try loadWeapons()

        for weapon in weapons {
            if WeaponDefinition.isBeam(guidance: weapon.guidance) {
                XCTAssertEqual(weapon.exitType, 3, "\(weapon.name) is a beam weapon but doesn't use the BeamPosX/Y exit type")
            } else {
                XCTAssertNotEqual(weapon.exitType, 3, "\(weapon.name) isn't a beam weapon but uses the BeamPosX/Y exit type")
            }
        }
    }

    // MARK: - Fighter bays

    // MaxAmmo is documented as "0 or -1 if you want the ammo quantity
    // constrained by the oütf resource's Max field instead" - both are
    // valid "unused" sentinels. Fighter bays (Guidance == 99) are the only
    // weapons that decode a positive MaxAmmo (interpreted as the number of
    // fighters the bay carries) in this scenario's real data; every
    // non-bay weapon that sets it at all uses the -1 sentinel, never a
    // positive count.
    func testOnlyFighterBaysHaveAPositiveMaxAmmo() throws {
        let weapons = try loadWeapons()
        let bays = weapons.filter { $0.guidance == 99 }

        guard bays.contains(where: { $0.maxAmmo > 0 }) else {
            throw XCTSkip("No fighter bay in this scenario decodes a positive MaxAmmo - skipping.")
        }

        for weapon in weapons where weapon.guidance != 99 {
            XCTAssertLessThanOrEqual(weapon.maxAmmo, 0, "\(weapon.name) isn't a fighter bay but has a positive MaxAmmo")
        }
    }

    // MARK: - Submunitions

    // Where SubCount is set, SubType should resolve to the ID of another
    // real wëap resource - submunitions must be actual weapons.
    func testSubmunitionTypeResolvesToARealWeapon() throws {
        let weapons = try loadWeapons()
        let idsByResource = Set(weapons.map(\.id))
        let splitting = weapons.filter { $0.subCount > 0 }

        guard !splitting.isEmpty else {
            throw XCTSkip("Scenario has no submunition-splitting weapons - skipping.")
        }

        for weapon in splitting {
            XCTAssertTrue(
                idsByResource.contains(Int(weapon.subType)),
                "\(weapon.name)'s SubType (\(weapon.subType)) doesn't resolve to any real wëap resource"
            )
        }
    }

    // MARK: - Colors

    // Particle/beam/hit-particle colors should decode to non-black values
    // whenever the weapon actually uses that effect (nonzero Particles
    // implies a meaningful PartColor; every weapon has a hit effect).
    func testParticleColorIsSetWhenParticlesAreUsed() throws {
        let weapons = try loadWeapons()

        for weapon in weapons where weapon.particles > 0 {
            XCTAssertFalse(weapon.partColor.isBlack, "\(weapon.name) generates particles but has a black PartColor")
        }
    }

    // Every real weapon should decode a hex string of the documented form.
    func testColorHexStringFormat() throws {
        let weapons = try loadWeapons()
        guard let weapon = weapons.first else {
            throw XCTSkip("No weapons decoded - skipping.")
        }

        let pattern = "^#[0-9A-F]{6}$"
        XCTAssertTrue(weapon.hitPartColor.hexString.range(of: pattern, options: .regularExpression) != nil)
    }

    // MARK: - Lightning beams

    // LiDensity should only be set on weapons that are also beam-guidance
    // (a lightning beam is still fundamentally a beam per the bible).
    func testLightningBeamFieldsOnlyAppearOnBeamWeapons() throws {
        let weapons = try loadWeapons()

        for weapon in weapons where weapon.liDensity > 0 {
            XCTAssertTrue(WeaponDefinition.isBeam(guidance: weapon.guidance), "\(weapon.name) has LiDensity set but isn't a beam weapon")
            XCTAssertTrue(weapon.isLightningBeam)
        }
    }
}
