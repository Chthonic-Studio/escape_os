class_name PacketLossMutator
extends CorruptionMutator

## Corruption Mutator: Packet Loss
##
## Intercepts npc_command_issued and comms_signal_sent signals.
## Each player command has a 30 % chance to be scrambled to a random
## signal type, creating unreliable NPC control at high corruption.

const SCRAMBLE_CHANCE: float = 0.30

func _init() -> void:
	mutator_id = &"packet_loss"
	display_name = "Packet Loss"
	description = "30% of comms signals are scrambled to a random type."
	stability_tier = 4

func _connect_hooks() -> void:
	EventBus.npc_command_issued.connect(_on_npc_command_issued)

func _on_run_end() -> void:
	if EventBus.npc_command_issued.is_connected(_on_npc_command_issued):
		EventBus.npc_command_issued.disconnect(_on_npc_command_issued)

## Randomly substitutes the command with another registered signal type.
## The scrambled command is applied via receive_comms_signal with the NPC's own
## room index so NPCs never path toward Vector2.ZERO (the invalid -1 room target).
## Since HumanController's npc_command_issued handler fires first (connected earlier),
## the scrambled call overrides the original state-machine transition in the same frame.
func _on_npc_command_issued(npc: Node, command: StringName) -> void:
	if randf() >= SCRAMBLE_CHANCE:
		return
	if not is_instance_valid(npc) or not npc.has_method("receive_comms_signal"):
		return
	var scrambled: StringName = CommsSystem.SIGNAL_TYPES.pick_random()
	## Use the NPC's actual room for a valid dispatch target.
	var room_index: int = -1
	if npc is Node2D:
		room_index = ShipData.get_room_at_world_pos((npc as Node2D).global_position)
	npc.receive_comms_signal(room_index, scrambled)
