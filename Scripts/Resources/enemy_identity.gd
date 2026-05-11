class_name EnemyIdentity
extends Resource

## Defines the full visual and behavioural identity for an enemy type.
## Assign to EnemyController.identity to swap enemy archetypes without
## touching controller code.  Replaces the need to subclass EnemyController.

@export_category("Identity")
@export var display_name: String = "Unknown Hostile"

## Optional SpriteFrames override; null = use the scene's default.
@export var sprite_frames: SpriteFrames = null

## Optional alternate enemy PackedScene (e.g. a giant or a swarm).  When set,
## EnemySpawnManager can instantiate this instead of the default enemy.tscn.
@export var enemy_scene: PackedScene = null

@export_category("Behaviour")
## The behaviour profile that controls movement, detection and attack stats.
@export var behavior_profile: EnemyBehaviorProfile = null
