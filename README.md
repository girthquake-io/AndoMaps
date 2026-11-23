<p align="center"><img src="Media/AndoMaps-logo.png" alt="AndoMaps" width="480"></p>

# AndoMaps — Route Finder for WoW Forever

**Type where you want to go. AndoMaps works out the quickest way there from wherever you're standing, then guides you step by step.**

Flight paths, boats, zeppelins, the Deeprun Tram, your Hearthstone, mage teleports and engineering transporters are all weighed together, so you get the genuinely fastest route, not just the closest flight master.

## Features

- **Quickest-route planning** to any town, zone, flight path, dungeon, raid or coordinates, mixing walking, flights, boats, zeppelins, the tram, portals and your Hearthstone (cooldowns included).
- **Only your flight paths**: learned automatically each time you open a flight master's map.
- **Every dungeon and raid entrance**, including WoW Forever's new instances (Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands, City of Dalaran, The Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace).
- **Forever's new zones**: flight paths in Mount Hyjal and the Riverglades; inns, banks and auction houses.
- **Nearest bank / auction house** with one click.
- **Teleports**: mage city teleports and portals; the Ultrasafe Transporter and Dimensional Ripper for engineers.
- **Auto-fly**: picks the right flight at the flight master (hold Shift to choose yourself).
- **"Get this flight path" tips** when a missing flight path would make a trip much faster; `/am missing` lists what you still need.
- **Arrow guidance**, optional TomTom waypoints and the in-game map pin.
- **World map button** (click anywhere to route there, works with OpenMap), Alt+click routing, minimap button and addon compartment entry.

## Slash commands

| Command | What it does |
|---|---|
| `/am` | Open or close the window |
| `/am <place>` | Route to a town, zone, dungeon or raid |
| `/am 45 60 Tanaris` | Route to coordinates |
| `/am pin` | Route to your world-map pin |
| `/am bank` · `/am ah` | Nearest bank or auction house |
| `/am next` · `/am prev` · `/am clear` | Step through or clear the route |
| `/am missing` | Flight paths you haven't picked up |
| `/am fptips` | Turn flight path tips on or off |
| `/am help` | Show all commands |

## Releasing

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager) (`.github/workflows/release.yml`):

1. Bump `## Version` in `AndoMaps.toc`.
2. Commit, then tag with the same number and push the tag:
   `git tag -a 2.12 -m "2.12" && git push --follow-tags`
3. GitHub Actions packages the addon (skipping the files listed in `.pkgmeta`) and uploads it to CurseForge and a GitHub release.

Needs the `CF_API_KEY` repository secret and `## X-Curse-Project-ID` in the TOC.
