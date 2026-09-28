import SwiftUI

// Standalone browser for every decoded wëap (weapon) resource found in the
// configured Nova Files folder. Not wired into the main pilot editor
// navigation yet - see WeaponDefinition for what's decoded and what isn't.
public struct WeaponCatalogView: View {
    @EnvironmentObject private var gameData: GameDataStore
    @State private var selectedWeaponID: Int?

    public init() {}

    private var weapons: [WeaponDefinition] { gameData.snapshot?.weapons ?? [] }

    public var body: some View {
        NavigationSplitView {
            listContent
                .navigationTitle("Weapons")
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            if let selectedWeaponID, let weapon = weapons.first(where: { $0.id == selectedWeaponID }) {
                WeaponDetailView(weapon: weapon)
            } else {
                Text("Select a weapon")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if let errorMessage = gameData.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if gameData.isLoading {
            ProgressView("Loading weapons…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if weapons.isEmpty {
            Text("No weapons found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(weapons, selection: $selectedWeaponID) { weapon in
                VStack(alignment: .leading, spacing: 4) {
                    Text(weapon.name)
                        .font(.headline)

                    HStack {
                        Text(WeaponDefinition.guidanceDescription(for: weapon.guidance))
                        Text("\u{00B7}")
                        Text("\(weapon.massDamage)M / \(weapon.energyDamage)E dmg")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(weapon.id)
            }
        }
    }

}

private struct WeaponDetailView: View {
    let weapon: WeaponDefinition

    var body: some View {
        Form {
            Section("Weapon") {
                LabeledContent("Name", value: weapon.name)
                LabeledContent("ID", value: "\(weapon.id)")
                LabeledContent("Guidance", value: "\(weapon.guidance) - \(WeaponDefinition.guidanceDescription(for: weapon.guidance))")
            }

            Section("Timing") {
                LabeledContent("Reload", value: "\(weapon.reload) frames")
                LabeledContent("Count (shot lifetime)", value: "\(weapon.count) frames")
            }

            Section("Damage") {
                LabeledContent("Mass Damage", value: "\(weapon.massDamage)")
                LabeledContent("Energy Damage", value: "\(weapon.energyDamage)")
                LabeledContent("Impact", value: "\(weapon.impact)")
            }

            Section("Flight") {
                LabeledContent("Speed", value: "\(weapon.speed) (px/frame x100)")
                LabeledContent("Ammo Type", value: "\(weapon.ammoType)")
            }

            Section("Impact") {
                LabeledContent("Explosion Type", value: "\(weapon.explodType)")
                LabeledContent("Proximity Radius", value: "\(weapon.proxRadius)")
                LabeledContent("Blast Radius", value: "\(weapon.blastRadius)")
            }

            Section("Presentation") {
                LabeledContent("Graphic Set", value: "\(weapon.graphic)")
                LabeledContent("Inaccuracy", value: "\(weapon.inaccuracy)\u{00B0}")
                LabeledContent("Sound", value: "\(weapon.sound)")
            }

            Section("Firing Behavior") {
                LabeledContent("Exit Point", value: WeaponDefinition.exitTypeDescription(for: weapon.exitType))
                LabeledContent("Burst Count / Reload", value: "\(weapon.burstCount) / \(weapon.burstReload)")

                if !WeaponDefinition.activeFlags(for: weapon.flags).isEmpty {
                    ForEach(WeaponDefinition.activeFlags(for: weapon.flags), id: \.self) { description in
                        Text("\u{2022} \(description)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if weapon.guidance == 1 {
                Section("Guided Weapon") {
                    LabeledContent("Guided Turn Rate", value: "\(weapon.guidedTurn)")
                    LabeledContent("Durability (PD hits)", value: "\(weapon.durability)")

                    if !WeaponDefinition.activeSeekerBehaviors(for: weapon.seeker).isEmpty {
                        ForEach(WeaponDefinition.activeSeekerBehaviors(for: weapon.seeker), id: \.self) { description in
                            Text("\u{2022} \(description)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Jamming Vulnerability")
                        Spacer()
                        Text(weapon.jamVulnerabilities.map { "\($0)%" }.joined(separator: " / "))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if weapon.guidance == 99 {
                Section("Fighter Bay") {
                    LabeledContent("Ship Class (AmmoType)", value: "\(weapon.ammoType)")
                    LabeledContent("Max Fighters Carried", value: "\(weapon.maxAmmo)")
                }
            }

            if WeaponDefinition.isBeam(guidance: weapon.guidance) {
                Section("Beam") {
                    LabeledContent("Length", value: "\(weapon.beamLength) px")
                    LabeledContent("Width", value: "\(weapon.beamWidth) px")
                    LabeledContent("Corona Falloff", value: "\(weapon.falloff)")

                    ColorSwatchRow(label: "Beam Color", color: weapon.beamColor)

                    if weapon.isLightningBeam {
                        LabeledContent("Lightning Density", value: "\(weapon.liDensity) zig-zags/100px")
                        LabeledContent("Lightning Amplitude", value: "\(weapon.liAmplitude) px")
                    } else {
                        ColorSwatchRow(label: "Corona Color", color: weapon.coronaColor)
                    }
                }
            }

            if weapon.particles > 0 {
                Section("Particle Trail") {
                    LabeledContent("Particles / Frame", value: "\(weapon.particles)")
                    LabeledContent("Particle Velocity", value: "\(weapon.partVel)")
                    LabeledContent("Particle Life", value: "\(weapon.partLifeMin)-\(weapon.partLifeMax) frames")
                    ColorSwatchRow(label: "Particle Color", color: weapon.partColor)
                }
            }

            Section("Impact Effects") {
                LabeledContent("Ionization", value: "\(weapon.ionization)")
                LabeledContent("Hit Particles", value: "\(weapon.hitParticles)")
                LabeledContent("Hit Particle Life", value: "\(weapon.hitPartLife) frames")
                LabeledContent("Hit Particle Velocity", value: "\(weapon.hitPartVel)")
                ColorSwatchRow(label: "Hit Particle Color", color: weapon.hitPartColor)

                if weapon.smokeSet >= 0 {
                    LabeledContent("Smoke Set", value: "\(weapon.smokeSet)")
                }
                if weapon.decay > 0 {
                    LabeledContent("Decay", value: "1 dmg every \(weapon.decay) frames")
                }
            }

            if weapon.subCount > 0 {
                Section("Submunitions") {
                    LabeledContent("Count", value: "\(weapon.subCount)")
                    LabeledContent("Sub-Weapon ID", value: "\(weapon.subType)")
                    LabeledContent("Angular Spread", value: "\(weapon.subTheta)\u{00B0}")
                    LabeledContent("Recursion Limit", value: "\(weapon.subLimit)")
                }
            }

            if !weapon.ionizeColor.isBlack {
                Section("Ionization Effect") {
                    ColorSwatchRow(label: "Ionize Color", color: weapon.ionizeColor)
                }
            }

            if !WeaponDefinition.activeFlags2(for: weapon.flags2).isEmpty || !WeaponDefinition.activeFlags3(for: weapon.flags3).isEmpty {
                Section("Additional Flags") {
                    ForEach(WeaponDefinition.activeFlags2(for: weapon.flags2), id: \.self) { description in
                        Text("\u{2022} \(description)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(WeaponDefinition.activeFlags3(for: weapon.flags3), id: \.self) { description in
                        Text("\u{2022} \(description)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(weapon.name)
    }
}

// Small color-swatch + hex-code row, used throughout the detail view for
// the resource's several RGBColor fields.
private struct ColorSwatchRow: View {
    let label: String
    let color: WeaponDefinition.RGBColor

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255))
                    .frame(width: 18, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary, lineWidth: 0.5))

                Text(color.hexString)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
