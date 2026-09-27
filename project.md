# EV Nova Pilot Editor

A native macOS editor and reference browser for EV Nova. The app edits pilot
files in place with a one-time backup per editing session and reads the game's
`.rez` archives for ship, outfit, weapon, and mission metadata.

## Current capabilities

- Pilots tab (`Views/Pilot/`): pick a pilot from the sidebar list (five
  rows, then it scrolls; each row has a reload button that re-reads the
  file from disk, for when the game has saved it), then edit it by section:
  - Pilot & Ship: nickname, gender, strict play, credits, rating, ship type,
    ship name, fuel (capacity includes fuel-tank outfits), paint, last
    planet, date.
  - Outfits & Weapons, Escorts & Fighters (including standing orders).
  - Current Missions: flags, reward (special negative pay codes explained),
    deadline, removal, and a jump to the mission's story chain.
  - Story Chains: every chain with a storyline label (from the scenario's
    ";tag" mission-name notes), drawn as a top-to-bottom flowchart
    (`MissionChainLayout` places it, `MissionChainGraphView` draws it) with
    per-mission status (active, available, completed, stuck, not reached
    yet, can't happen). The chart is dragged around (or moved with a
    trackpad or mouse wheel) instead of scrolled, and opens with the
    story's start centred at the top. A "Done" switch in the details pane
    marks a mission done or not done by applying (or undoing) the story
    flags its accept and success outcomes set (`MissionCompletion`); shared
    flags are left alone when undoing, and non-flag effects are only
    reported. Under the switch, the mission's text (offer, accept,
    briefing, cargo, completion; from the scenario's dësc resources via
    `MissionText`) is shown with its {bXXX "..." "..."} switches applied
    for the pilot. Every flag mention names its kind ("story flag 285"),
    since flag numbers overlap mission numbers. Clicking a box shows its unmet requirements,
    conflicting branches, and flag toggles in a pane below the chart.
  - Chains follow both "start mission" commands and flag links (one
    mission's success turns on a flag another waits for). Flags that more
    than 3 missions turn on are treated as shared markers and never link.
    Chains are grouped by storyline tag, so linked storylines stay
    separate groups.
  - When a mission needs a flag off and a mission you actually did turned
    it on, the diagnosis explains the lock. Shared "main storyline in
    progress" flags (511, 515, 518) are named by storyline ("A main
    storyline is still in progress (Auroran)"). Ways out only list what
    the player can cause: completing, accepting, refusing (unless the
    mission can't be refused), aborting (only when allowed; missions whose
    abort does nothing are marked), and failing only when the mission can
    fail (time limit, escort/rescue/disable/board goals, scan or pirate
    boarding flags). When nothing can clear it, it says so, and later
    steps of the holding storyline are named only if they can still come
    up (branches the story went past are skipped).
  - Each lock has a "Fix in editor" button that copies a real mission
    outcome clearing every lock flag (preferring missions you can take now
    and the holding storyline), with a preview; it falls back to clearing
    the flags. A "How to get this mission" checklist in the details pane
    lists the lock, story requirements, place, chance, combat rating and
    ship rules. Chains stopped by a lock show "Locked out" in the chain
    list, and the chart header links to the mission holding the lock.
  - Ship offer rules: missions flagged "needs cargo space", "not for cargo
    ships/warships", or "takes 100 fuel" are checked against the pilot's
    ship. Cargo space, fuel, and free mass (`ShipCapacity`) count owned
    outfits (cargo pods, mass expansions such as the Mass Retool, fuel
    tanks, ship-mass-scaled armor), goods aboard, and active mission cargo.
  - Story Flags, Systems & Planets, Characters, Ranks/Events/Prices.
  - Edits are written only with the "Save Pilot Changes" toolbar button
    (disabled until something changes).
- Map tab (`Views/GalaxyMapView.swift`): every system at its in-game map
  position with its hyperlinks (`GalaxyMap` decodes sÿst positions, links,
  planets, and government). Search systems and planets, click a star for
  its planets and neighbours, drag to move, scroll to zoom around the
  pointer. Opens zoomed to fit the whole galaxy. Every system is labelled;
  a name that would overlap another shows once zoomed in. A green ring
  marks the open pilot's system (from their last planet or station), and
  "My System" jumps to it. "Find on Map"
  on a mission (Story Chains header, Current Missions) switches to the map
  and rings where it's offered, where it goes, where to return, and where
  its special ships are (`MissionMapLocations`). Current Missions uses the
  planets the live mission picked. Codes that aren't one place ("any
  planet of X" marks all of X's systems; random planets mark nothing) are
  explained in the sidebar.
- Story-flag metadata is derived from the loaded scenario's expressions
  (missions, ships, outfits, events, disasters, characters, planets, systems,
  fleets, junk), so plugin flags are supported too.
- Plug-ins in the "Nova Plug-ins" folder (subfolders included) load after
  Nova Files. A resource defined more than once uses the last copy loaded,
  so plug-ins override the base game.
- On first launch (or if the saved folder is no longer valid), prompt for the
  EV Nova install folder. The Pilots, Nova Files, and Nova Plug-ins folders
  are derived from it; change it later in Settings.
- Browse ships, outfits, weapons, and every decoded mission definition.
- Browse complete mission-chain components, including success, failure,
  accept, refuse, abort, and ship-objective branches; cyclic chains are safe.
- Parse immutable Nova game assets once at application launch and share one
  precomputed snapshot across every catalog and pilot-editor lookup.

The old raw-bytes inspector and schema-driven field list were removed from
the UI; `FieldSchema.json` still backs the scalar fields.

## Safety model

Edits are made to an in-memory copy. Each write is applied atomically to a
scratch buffer first, and saving creates a backup before replacing the source
pilot file. Unknown bytes are preserved byte-for-byte.

## Development

Requires macOS 14 and Swift 5.10 or newer.

```sh
swift test
swift run EVNPilotEditor
```

Known uncertain areas: last planet and the date prefix/suffix offsets are
probable rather than in-game verified, the price-swing arrays are
undocumented, "completed" mission status is inferred from story flags, and
mission 428 in the stock data is malformed.

Verified fields are edited freely. Probable fields (offsets inferred from the
format notes and sample pilots but not yet confirmed by an in-game change) are
editable too, but every section that edits one carries an "inferred, not yet
confirmed" note (`UnconfirmedFieldNote`) so the backup is kept until the result
is checked. Unsupported or still-unidentified pilot fields should be
documented and tested before they are exposed for writes.
