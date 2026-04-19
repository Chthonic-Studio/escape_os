class_name NPCPersonality
extends RefCounted

enum Type {
	NORMAL,
	BRAVE,
	COWARD,
	RECKLESS,
}

## Weighted distribution for random assignment.
const WEIGHTS: Dictionary = {
	Type.NORMAL: 5.0,
	Type.BRAVE: 2.0,
	Type.COWARD: 2.0,
	Type.RECKLESS: 1.0,
}

static func pick_random() -> Type:
	var total: float = 0.0
	for w in WEIGHTS.values():
		total += w

	var roll: float = randf_range(0.0, total)
	var accum: float = 0.0
	for ptype in WEIGHTS.keys():
		accum += WEIGHTS[ptype]
		if roll <= accum:
			return ptype

	return Type.NORMAL

static func get_name(ptype: Type) -> String:
	match ptype:
		Type.NORMAL: return "Normal"
		Type.BRAVE: return "Brave"
		Type.COWARD: return "Coward"
		Type.RECKLESS: return "Reckless"
	return "Unknown"
