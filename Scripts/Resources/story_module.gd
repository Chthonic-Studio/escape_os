class_name StoryModule
extends Resource

## A piece of narrative lore that can be unlocked during a run and viewed in
## the Hub's log panel.

@export_category("Identity")
@export var module_id: StringName = &""
@export var title: String = "Log Entry"
@export var log_text: String = ""

@export_category("Unlock")
## EventBus signal name whose emission unlocks this module.
## e.g. &"npc_killed_by_enemy", &"enemies_have_spawned"
@export var unlock_condition: StringName = &""
## Optional minimum count of the unlock_condition event before this unlocks.
@export var unlock_count: int = 1
