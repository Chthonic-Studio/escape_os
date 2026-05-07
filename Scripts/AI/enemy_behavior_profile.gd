class_name EnemyBehaviorProfile
extends Resource

## Tunable parameters that define how an enemy type behaves.
## Assign an instance of this resource to EnemyController.behavior_profile
## to override per-enemy defaults without touching the controller script.

## Movement speed while hunting survivors.
@export var chase_speed: float = 70.0

## Distance at which the enemy can deal kill damage to a target.
@export var kill_range: float = 24.0

## Local perception range — enemies detect survivors within this distance (pixels).
@export var detection_range: float = 250.0

## Damage dealt per second to survivors in kill range or via collision.
@export var damage_per_second: float = 40.0

## Minimum seconds the enemy rests after a kill before resuming the hunt.
@export var rest_duration_min: float = 3.0

## Maximum seconds the enemy rests after a kill before resuming the hunt.
@export var rest_duration_max: float = 5.0

## 0.0–1.0 probability this enemy will act on a hint from the Enemy Director
## when it is idle or resting.  Lower values make the enemy more self-reliant
## and less responsive to global guidance.
@export_range(0.0, 1.0) var hint_receptiveness: float = 0.85

## Whether this enemy type will attempt to break through closed doors when
## it cannot reach a target.  Set to false for enemy types that cannot force
## doors open.
@export var can_break_doors: bool = true
