extends Node

## The corporate priority hierarchy for the Shareholder Value Assessment.

## Priority order from highest to lowest value. Maps class_name_id → priority rank.
var priority_order: Array[StringName] = [
	&"captain",
	&"engineer",
	&"nepotism_hire",
	&"influencer",
	&"Passenger",
	&"Crewmember",
	&"intern",
	&"janitor",
	&"thief",
]

func get_priority_rank(class_id: StringName) -> int:
	var idx: int = priority_order.find(class_id)
	return idx

func get_sorted_results(class_results: Dictionary) -> Array[Dictionary]:
	var sorted: Array[Dictionary] = []
	for class_id in priority_order:
		if class_results.has(class_id):
			var entry: Dictionary = class_results[class_id].duplicate()
			entry["class_id"] = class_id
			entry["rank"] = get_priority_rank(class_id)
			sorted.append(entry)
	for class_id in class_results:
		if class_id not in priority_order:
			var entry: Dictionary = class_results[class_id].duplicate()
			entry["class_id"] = class_id
			entry["rank"] = priority_order.size()
			sorted.append(entry)
	return sorted

func get_display_name(class_id: StringName) -> String:
	match class_id:
		&"captain": return "Ship Captain"
		&"engineer": return "Lead Engineer"
		&"nepotism_hire": return "Nepotism Hire"
		&"influencer": return "Influencer"
		&"Passenger": return "Passenger"
		&"Crewmember": return "Crewmember"
		&"intern": return "Intern"
		&"janitor": return "Janitor"
		&"thief": return "CPU Fan Thief"
	return str(class_id).capitalize()
