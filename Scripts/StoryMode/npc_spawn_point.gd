class_name NpcSpawnPoint
extends Node2D

## Marks a specific spawn location for an NPC in a story-mode level.
##
## Place as a child of StoryLevelController (or a container child).
## If no NpcSpawnPoint nodes exist, StoryLevelController spawns NPCs
## automatically throughout the rooms.

@export_category("NPC Assignment")
## The NPCClass resource to use for this spawn. Leave empty to pick randomly
## from the StoryLevelController's npc_classes array.
@export var npc_class: NPCClass = null

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_circle(Vector2.ZERO, 5.0, Color(0.3, 1.0, 0.3, 0.8))
	draw_string(ThemeDB.fallback_font, Vector2(-10, -10), "NPC",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.3, 1.0, 0.3))
