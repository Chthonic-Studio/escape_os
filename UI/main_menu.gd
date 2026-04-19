class_name MainMenu
extends CanvasLayer

## Main menu with difficulty selection.

func _ready() -> void:
	layer = 100
	_refresh_max_scores()
	var menu_music := load("res://Assets/Audio/LD59MainMenu.wav") as AudioStream
	if menu_music:
		AudioManager.play_music(menu_music)

func _get_max_score_labels_by_difficulty() -> Dictionary:
	return {
		"Easy": get_node_or_null("CenterContainer/VBox/MaxScoreRow/EasyMaxScore"),
		"Medium": get_node_or_null("CenterContainer/VBox/MaxScoreRow/MediumMaxScore"),
		"Hard": get_node_or_null("CenterContainer/VBox/MaxScoreRow/HardMaxScore"),
	}

func _refresh_max_scores() -> void:
	var labels_by_difficulty := _get_max_score_labels_by_difficulty()
	for difficulty_name in UIManager.DIFFICULTY_CONFIGS.keys():
		var label: Label = labels_by_difficulty.get(difficulty_name)
		if label == null:
			continue
		var best = UIManager.get_max_score(difficulty_name)
		if best == null:
			label.text = "BEST: —"
		else:
			label.text = "BEST: %.1f SHV" % float(best)

func _on_difficulty_selected(difficulty_name: String) -> void:
	UIManager.set_difficulty(difficulty_name)
	EventBus.game_start_requested.emit()
	queue_free()

func _on_exit_pressed() -> void:
	get_tree().quit()
