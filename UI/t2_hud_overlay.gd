class_name T2HudOverlay
extends VBoxContainer

## T2-style HUD overlay: threat level, real-time score.

@onready var _threat_label: Label = $ThreatLabel
@onready var _score_label: Label = $ScoreLabel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	_update_threat()
	_update_score()

	if _threat_label:
		if TimeManager.is_paused:
			_threat_label.text = "▮▮ PAUSED"
			_threat_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))

func _update_threat() -> void:
	if TimeManager.is_paused:
		return
	var enemies: int = GameManager.enemies_alive

	if enemies == 0:
		_threat_label.text = "THREAT LEVEL: NOMINAL"
		_threat_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 0.8))
	elif enemies <= 3:
		_threat_label.text = "THREAT LEVEL: ELEVATED"
		_threat_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 0.8))
	elif enemies <= 8:
		_threat_label.text = "THREAT LEVEL: HIGH"
		_threat_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2, 0.8))
	else:
		_threat_label.text = "THREAT LEVEL: CRITICAL"
		_threat_label.add_theme_color_override("font_color", Color(1.0, 0.1, 0.1, 1.0))

func _update_score() -> void:
	var value: float = GameManager.get_shareholder_value()
	var color: Color
	if value >= 0:
		color = Color(1.0, 0.85, 0.0, 0.8)
		_score_label.text = "SHV: +%.1f" % value
	else:
		color = Color(1.0, 0.3, 0.3, 0.8)
		_score_label.text = "SHV: %.1f" % value
	_score_label.add_theme_color_override("font_color", color)
