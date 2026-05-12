class_name PermanentUpgrade
extends Resource

## A single purchasable permanent upgrade available in the Hub between runs.

@export_category("Identity")
@export var upgrade_id: StringName = &""
@export var display_name: String = "Upgrade"
@export var description: String = ""

@export_category("Cost")
@export var cost_shv: float = 10.0

@export_category("Effect")
## Identifies what the upgrade does, e.g. "npc_speed", "max_pods", "enemy_stun_duration".
@export var effect_type: StringName = &""
## Magnitude of the effect (interpretation depends on effect_type).
@export var effect_value: float = 0.1

@export_category("Progression")
## Maximum number of times this upgrade may be purchased.
@export var max_level: int = 1
