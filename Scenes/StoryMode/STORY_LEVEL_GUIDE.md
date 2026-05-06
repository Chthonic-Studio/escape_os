# Story Mode Level Creation Guide

This guide walks you through everything needed to create a new story-mode level, register it in a story campaign, and have it show up in the in-game story selection screen.

---

## Table of Contents

1. [Overview of the story mode pipeline](#1-overview)
2. [File and folder locations](#2-file-and-folder-locations)
3. [Step 1 — Duplicate the level template](#step-1--duplicate-the-level-template)
4. [Step 2 — Paint the ship tilemap](#step-2--paint-the-ship-tilemap)
5. [Step 3 — Add RoomMarkers](#step-3--add-roommarkers)
6. [Step 4 — Place Doors](#step-4--place-doors)
7. [Step 5 — Place Escape Pods](#step-5--place-escape-pods)
8. [Step 6 — Place NPC Spawn Points (optional)](#step-6--place-npc-spawn-points-optional)
9. [Step 7 — Tune gameplay variables](#step-7--tune-gameplay-variables)
10. [Step 8 — Create a StoryLevelData resource](#step-8--create-a-storyleveldata-resource)
11. [Step 9 — Create or update a StoryData resource](#step-9--create-or-update-a-storydata-resource)
12. [Step 10 — Verify it appears in-game](#step-10--verify-it-appears-in-game)
13. [Reference: Gameplay variables cheatsheet](#reference-gameplay-variables-cheatsheet)
14. [Reference: Room types](#reference-room-types)
15. [Reference: Available NPC classes](#reference-available-npc-classes)
16. [Troubleshooting](#troubleshooting)

---

## 1. Overview

Story mode levels are **hand-crafted scenes** that run through the same AI, pathfinding, and gameplay logic as the procedurally generated arcade mode. The key difference is that *you* design the ship layout instead of the generator doing it.

The pipeline looks like this:

```
story_level_base.tscn (template)
        ↓  duplicate
my_level.tscn            ← you design the ship here
        ↓  referenced by
my_level.tres            ← StoryLevelData resource (name, description, scene path)
        ↓  referenced by
my_story.tres            ← StoryData resource (campaign name, ordered level list)
        ↓  placed in
Resources/Stories/       ← auto-discovered by the story selection screen
```

---

## 2. File and Folder Locations

| What | Where |
|---|---|
| Level template scene | `Scenes/StoryMode/story_level_base.tscn` |
| Your level scenes | `Scenes/StoryMode/` (recommended) |
| StoryLevelData resources | `Resources/Stories/` |
| StoryData resources | `Resources/Stories/` |
| `StoryLevelController` script | `Scripts/StoryMode/story_level_controller.gd` |
| `RoomMarker` script | `Scripts/StoryMode/room_marker.gd` |
| `NpcSpawnPoint` script | `Scripts/StoryMode/npc_spawn_point.gd` |
| NPC class resources | `Resources/NPC/` |

---

## Step 1 — Duplicate the Level Template

1. In the **FileSystem** dock, navigate to `Scenes/StoryMode/`.
2. Right-click `story_level_base.tscn` and choose **Duplicate** (`Ctrl+D`).
3. Rename the duplicate to something descriptive, e.g. `chapter1_level1.tscn`.
4. Open the new scene.

The scene tree will look like this:

```
StoryLevel  (StoryLevelController)
├── ParallaxNebula
│   └── NebulaSprite
├── ParallaxStars
│   └── StarsSprite
├── TileMapLayer          ← paint your ship here
├── NavigationRegion2D    ← nav mesh is baked automatically
├── RoomMarkers           ← add RoomMarker children here
├── Doors                 ← instance door.tscn children here
├── EscapePods            ← instance escape_pod.tscn children here
├── NpcSpawnPoints        ← optional: instance NpcSpawnPoint children here
├── Camera2D
└── CameraBounds
```

---

## Step 2 — Paint the Ship Tilemap

Select the **TileMapLayer** node. The template already has a TileSet with two sources:

| Source ID | Tile | What it does |
|---|---|---|
| `0` | `LD59_WallTile.png` | Wall (blocks movement, AI treats as impassable) |
| `1` | `LD59_FloorBasicTile.png` | Floor (walkable area, used for navigation) |

Paint your entire ship using these tiles:
- Use **source 1 (floor)** for every room interior and corridor.
- Use **source 0 (wall)** to border the ship and fill in any solid areas.

> **Tip — leave walls to auto-derive:** If you do not paint any wall tiles (source 0), `StoryLevelController` will automatically generate wall cells by scanning the neighbours of every floor cell. This is convenient for quick iteration.

The `floor_tile_source_id` and `wall_tile_source_id` export variables on the root `StoryLevel` node control which source IDs are treated as floor vs wall. Default values (`1` and `0`) match the template tileset.

---

## Step 3 — Add RoomMarkers

Every distinct room must have a **RoomMarker** child so the pathfinder and enemy AI can reason about room connectivity.

1. Select the `RoomMarkers` node.
2. Add a child node of type `Node2D`.
3. In the **Inspector**, attach the script `Scripts/StoryMode/room_marker.gd`.
4. Set the properties:

| Property | Description |
|---|---|
| `room_rect_tiles` | `Rect2i(x, y, width, height)` in **tile coordinates** matching your painted floor area |
| `room_type` | One of the types listed in [Reference: Room types](#reference-room-types) |
| `is_outer_room` | Set to `true` if the room is on the outer edge of the ship (required for escape pod eligibility and pod respawning) |

The editor will draw a tinted blue overlay showing exactly where the room bounds are, with the room type label in the corner.

**Rules:**
- Add one `RoomMarker` per logical room (not per corridor).
- `room_rect_tiles` should tightly wrap the painted floor tiles of that room.
- At least one room must have `is_outer_room = true` for escape pods to work.
- Rooms can overlap slightly at corridors — the pathfinder will still connect them via the doors you place.

---

## Step 4 — Place Doors

Doors are the connection points between rooms that the AI uses for navigation.

1. Select the `Doors` node.
2. **Instance** `Scenes/door.tscn` as a child (`Ctrl+Shift+A` → search "door").
3. Position the door **on the boundary between two rooms**.
4. Rotate the door 90° if the doorway is horizontal.

> **Auto-connection:** `StoryLevelController` automatically finds which room(s) each door belongs to by expanding each room rect by 2 tiles on all sides. You do not need to manually assign `room_a_index` / `room_b_index` — the controller does this at runtime.

**Tips:**
- Doors should be placed roughly in the centre of a corridor between rooms.
- One door per corridor is sufficient.
- Doors can be rotated freely.

---

## Step 5 — Place Escape Pods

Escape pods are where crew members escape. Place at least one per level.

1. Select the `EscapePods` node.
2. **Instance** `Scenes/escape_pod.tscn` as a child.
3. Position the pod near an outer-room wall or corridor end.

> The room the pod sits in is automatically added to `ShipData.outer_room_indices` so enemy spawns avoid it and the pod-respawn system works.

**Capacity override:** If you want all pods in this level to have a specific capacity, set `escape_pod_capacity_override` on the root `StoryLevel` node (e.g. `4` for 4 seats). Leave at `0` to use each pod's own default value.

---

## Step 6 — Place NPC Spawn Points (optional)

By default, `StoryLevelController` spawns `npc_count` NPCs randomly distributed across all rooms, each assigned a random class from `npc_classes`.

If you want precise placement or class control:

1. Select the `NpcSpawnPoints` node.
2. **Instance** a `Node2D` child and attach `Scripts/StoryMode/npc_spawn_point.gd`.
3. Position the node exactly where the NPC should start.
4. Optionally assign a specific `npc_class` resource in the **Inspector** (leave empty for random).

> **Important:** If *any* `NpcSpawnPoint` children exist, the auto-spawn system is skipped entirely. You control exactly how many NPCs there are and where they stand.

A small green circle marks each spawn point in the editor.

---

## Step 7 — Tune Gameplay Variables

Select the root **StoryLevel** node. The Inspector shows all tunable gameplay variables under their respective categories. These override the default values and are then further scaled by the player's selected difficulty at runtime.

See [Reference: Gameplay variables cheatsheet](#reference-gameplay-variables-cheatsheet) below for the full list.

---

## Step 8 — Create a StoryLevelData Resource

This resource holds the level's display name, description, and the path to the `.tscn` you just made.

1. In the **FileSystem** dock, navigate to `Resources/Stories/`.
2. Right-click → **New Resource** → search for `StoryLevelData` → **Create**.
3. Name it something like `chapter1_level1.tres`.
4. In the Inspector, fill in:

| Property | Value |
|---|---|
| `level_name` | e.g. `"The Outbreak"` |
| `level_description` | The description shown when the player hovers over this level in the selection screen |
| `level_scene_path` | Path to your `.tscn`, e.g. `res://Scenes/StoryMode/chapter1_level1.tscn` |

> Click the folder icon next to `level_scene_path` to browse and select the `.tscn` directly.

---

## Step 9 — Create or Update a StoryData Resource

A `StoryData` resource represents a full campaign. It holds the story name, description, and an **ordered array of StoryLevelData** resources.

### Creating a new story

1. In `Resources/Stories/`, right-click → **New Resource** → `StoryData` → **Create**.
2. Name it e.g. `my_story.tres`.
3. Fill in:

| Property | Value |
|---|---|
| `story_name` | Display name shown on the story selection screen |
| `story_subtitle` | Short tagline shown below the name |
| `story_description` | Full description shown when the player hovers over this story |
| `story_id` | A **unique** `StringName` used for progress tracking, e.g. `&"chapter_1"`. Do not reuse IDs. |
| `levels` | Array of `StoryLevelData` resources — **order matters**. Level 0 is always unlocked; subsequent levels unlock after the previous one is completed. |

### Adding a level to an existing story

1. Open the existing `StoryData` .tres file (e.g. `placeholder_story.tres`).
2. In the Inspector, expand the `levels` array.
3. Click **Add Element** and assign your new `StoryLevelData` resource.
4. Drag to reorder if needed.

> **Placement is automatic.** The story selection screen (`UI/story_select.gd`) reads every `.tres` file inside `Resources/Stories/` at startup. As long as your `.tres` file is in that folder, the story will appear in the menu — no code changes needed.

---

## Step 10 — Verify It Appears In-Game

1. Run the game.
2. Click **STORY MODE** on the main menu.
3. Your story should appear as a button on the left. Hover over it to see the description on the right.
4. Click the story → select a level → choose a difficulty → click **START MISSION**.
5. The loading screen will appear while the level sets up, then the game begins.

### In-game controls

| Key | Action |
|---|---|
| **Esc** | Open / close the **Pause Menu** (gameplay and AI freeze while open; Resume or Main Menu) |
| **R** (on assessment screen) | Open the **Restart Confirmation** popup |

If the story or level does not appear, check the [Troubleshooting](#troubleshooting) section below.

---

## Reference: Gameplay Variables Cheatsheet

These are all the `@export` variables on the root `StoryLevel` node (`StoryLevelController`):

### References
| Variable | Default | Description |
|---|---|---|
| `nav_region` | *(set in template)* | The `NavigationRegion2D` node. Do not change. |
| `visual_tilemap` | *(set in template)* | The `TileMapLayer` node. Do not change. |

### Tilemap Tile Source IDs
| Variable | Default | Description |
|---|---|---|
| `floor_tile_source_id` | `1` | TileSet source ID treated as walkable floor. |
| `wall_tile_source_id` | `0` | TileSet source ID treated as walls. Set to `-1` to auto-derive walls from floor neighbours. |

### Gameplay Variables
| Variable | Default | Description |
|---|---|---|
| `enemy_chase_speed` | `70.0` | Enemy movement speed in pixels/sec. |
| `enemy_spawn_delay` | `4.0` | Seconds before the **first** enemy spawns after the level starts. |
| `enemy_respawn_interval` | `20.0` | Seconds between enemy respawn checks. Scaled shorter at higher difficulty. |
| `max_enemies_alive` | `2` | Maximum number of enemies on screen at the same time. |
| `npc_speed_modifier` | `1.0` | Multiplier on all NPC walk/panic speeds. `1.5` = 50% faster. |
| `escalation_interval` | `30.0` | Seconds between automatic speed escalation steps. |
| `escalation_step` | `0.12` | How much the global speed multiplier increases each escalation step. |
| `escape_pod_capacity_override` | `0` | Force all pods in this level to have this capacity. `0` = use each pod's own value. |

### NPC Configuration
| Variable | Default | Description |
|---|---|---|
| `npc_scene` | `human.tscn` | The NPC packed scene to instantiate. Do not change unless you have a custom NPC. |
| `npc_classes` | *(all classes)* | Array of `NPCClass` resources to randomly assign. |
| `npc_count` | `10` | Number of NPCs to spawn when no `NpcSpawnPoint` children exist. |

---

## Reference: Room Types

Set on each `RoomMarker`. Affects AI behaviour and log feed messages.

| Value | Description |
|---|---|
| `GENERIC` | Default room with no special behaviour. |
| `BARRACKS` | Crew sleeping quarters. |
| `CAFETERIA` | Eating area. |
| `OFFICE` | Administrative area. |
| `MEDBAY` | Medical facility. |
| `ENGINE_ROOM` | Engine and machinery area. |
| `BRIDGE` | Ship command centre. |
| `CARGO_BAY` | Cargo storage. |
| `RECREATION` | Leisure area. |

---

## Reference: Available NPC Classes

Located in `Resources/NPC/`. Assign any combination to `npc_classes` on the `StoryLevel` node or to individual `NpcSpawnPoint` nodes.

| File | Class |
|---|---|
| `captain.tres` | Ship Captain — high corporate value |
| `engineer.tres` | Engineer |
| `crewmember.tres` | Generic crew member |
| `janitor.tres` | Janitor |
| `intern.tres` | Intern |
| `passenger.tres` | Passenger |
| `thief.tres` | Thief — negative corporate value |
| `influencer.tres` | Influencer — very high corporate value |
| `nepotism_hire.tres` | Nepotism hire — high value despite low competence |

---

## Troubleshooting

**Story does not appear on the story selection screen**
- Confirm the `.tres` file is saved inside `Resources/Stories/`.
- Confirm the resource type is `StoryData` (not `StoryLevelData` or a plain `Resource`).
- Confirm the `story_id` field is not empty.

**Level does not start / loading screen hangs forever**
- Confirm `level_scene_path` in the `StoryLevelData` resource points to the correct `.tscn`.
- Confirm the root node of that `.tscn` has `StoryLevelController` as its script.
- Confirm `nav_region` and `visual_tilemap` on the root node point to the correct child nodes.

**NPCs do not move or enemies do not spawn**
- Confirm at least one `RoomMarker` exists with a valid `room_rect_tiles`.
- Confirm at least one `EscapePod` instance is in the scene.
- Confirm `npc_scene` is set to `human.tscn` on the root `StoryLevel` node.

**NPCs clip through walls or navigation fails**
- Make sure every room's `room_rect_tiles` accurately matches the painted floor tiles — do not include wall cells in the rect.
- If rooms are very small (less than 4×4 tiles), NPCs may struggle to path through them.

**Doors do not connect rooms**
- Make sure each door is positioned within 2 tiles of a room boundary.
- Make sure both rooms on either side of the door have `RoomMarker` nodes whose `room_rect_tiles` cover the area around the door.

**Level unlocks are not saved**
- Progress is stored in `user://story_progress.json`. If the file is missing or corrupt, level 0 is always available but subsequent levels will appear locked.
- Ensure `story_id` on the `StoryData` resource is unique across all stories and has not changed since the player last completed a level.
