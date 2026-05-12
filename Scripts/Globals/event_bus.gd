extends Node

## Global signal bus.

## Ship layout changed, agents should repath.
@warning_ignore("unused_signal")
signal nav_graph_changed

@warning_ignore("unused_signal")
signal door_toggled(door_id: StringName, is_open: bool)

@warning_ignore("unused_signal")
signal door_destroyed(door_id: StringName, global_pos: Vector2)

@warning_ignore("unused_signal")
signal hazard_deployed(type: StringName, global_loc: Vector2)

@warning_ignore("unused_signal")
signal ship_generated(escape_pod_positions: Array[Vector2])

## Request to spawn a batch of enemies.
@warning_ignore("unused_signal")
signal enemy_spawn_requested(spawn_type: StringName, count: int)

## Where to spawn each enemy.
@warning_ignore("unused_signal")
signal enemy_spawn(global_pos: Vector2)

@warning_ignore("unused_signal")
signal npc_spawned(npc_class_id: StringName, global_pos: Vector2, room_type: int)

@warning_ignore("unused_signal")
signal airlock_activated(room_index: int)

@warning_ignore("unused_signal")
signal room_depressurized(room_index: int)

@warning_ignore("unused_signal")
signal room_repressurized(room_index: int)

@warning_ignore("unused_signal")
signal airlock_blocked(room_index: int)

@warning_ignore("unused_signal")
signal comms_mode_changed(active: bool)

## Emitted when the player clicks a room to signal NPCs.
@warning_ignore("unused_signal")
signal comms_signal_sent(room_index: int, affected_room_indices: Array)

@warning_ignore("unused_signal")
signal npc_state_changed(npc: Node, new_state: StringName)

@warning_ignore("unused_signal")
signal npc_died(npc: Node)

@warning_ignore("unused_signal")
signal vip_killed(npc: Node)

@warning_ignore("unused_signal")
signal npc_escaped(npc: Node)

@warning_ignore("unused_signal")
signal npc_killed_by_enemy(npc: Node, global_pos: Vector2)

@warning_ignore("unused_signal")
signal enemy_died(enemy: Node)

@warning_ignore("unused_signal")
signal enemies_have_spawned

@warning_ignore("unused_signal")
signal game_start_requested

## Emitted by ShipGenerator during level build so the loading screen can show progress.
@warning_ignore("unused_signal")
signal generation_progress(step: String, pct: float)

## Emitted from HumanController._ready() so ShipData can maintain its NPC cache.
@warning_ignore("unused_signal")
signal npc_ready(npc: Node)

## Emitted from EnemyController._ready() so ShipData can maintain its enemy cache.
@warning_ignore("unused_signal")
signal enemy_ready(enemy: Node)

## Emitted when a story level is successfully loaded and about to start.
@warning_ignore("unused_signal")
signal story_level_started(story_id: StringName, level_index: int)

## Emitted when a player issues a direct command to an NPC (radial menu or
## other direct-command path).  PacketLossMutator intercepts this signal.
@warning_ignore("unused_signal")
signal npc_command_issued(npc: Node, command: StringName)

## Run lifecycle signals.
@warning_ignore("unused_signal")
signal run_started(run_data: RunData)

@warning_ignore("unused_signal")
signal run_ended(run_data: RunData)
