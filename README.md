# Many Mission Terminal

Surfaces every joinable mission on the Darktide mission board, not just the 16 the vanilla board has
slots for.

## What it does

- **Every map on one board.** The tile pool is grown and missions are laid out one tile per map, with
  a count badge when a map has more than one mission going.
- **Mission list.** Click a map to open a sortable table of its missions: time remaining, type,
  circumstance, side objective, and an icon per condition.
- **Filter panel.** Press **F** (Left Trigger / L2) to open the drawer, again to switch tabs, again to
  close it.
  - **Filters** decides what the board shows: mission type, condition, and side objective, with a
    match-any/match-all toggle. Campaign missions are hidden by default.
  - **Exclusions** decides what Quickplay refuses. Tick any map or condition and Quickplay will not
    put you in it.
- **Quickplay screening.** When Exclusions are set, the mod inspects each mission you are matched into
  before the map loads. If it matches an exclusion it leaves the party and searches again, and it
  remembers what it rejected so the same mission is not retried.
- **Recently expired missions** stay joinable for a grace window and are listed under the live ones.
- **Bookmarks.** If [Many More Try](https://www.nexusmods.com/warhammer40kdarktide/mods/376) is
  installed, missions you have saved with it are marked in the list.

## Options

On the mission board's own options page:

- **Only Start New Missions** - Quickplay will leave and search again if it matches you into a mission
  that is already underway.

In the mod options menu:

- **Recently Expired** - include recently expired missions, which are still joinable for a while.
- **Announce skipped Quickplay missions** - show a notification each time a mission is skipped, and
  why.

## Requires

Nothing. [Many More Try](https://www.nexusmods.com/warhammer40kdarktide/mods/376) is optional - it
adds the bookmark column and lets you re-queue a saved mission from chat.

## Incompatible with

Other mods that rearrange the mission board (MissionGrid, StoryReplay, sorted_mission_grid). The mod
warns in-game if it detects one.

Plays nicely with [Quickest Play](https://www.nexusmods.com/warhammer40kdarktide/mods/105) - when a
mission is skipped, its auto-queue is cancelled first so the two do not fight over the party.
