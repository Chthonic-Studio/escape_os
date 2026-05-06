class_name AssessmentScreen
extends CanvasLayer

## Post-game "Shareholder Value Assessment" screen.

const RESTART_CONFIRM_SCENE = preload("res://Scenes/restart_confirm.tscn")

@onready var _title_label: Label = $Background/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var _summary_label: Label = $Background/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SummaryLabel
@onready var _class_breakdown: VBoxContainer = $Background/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ClassBreakdown
@onready var _total_label: Label = $Background/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TotalLabel
@onready var _grade_label: Label = $Background/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/GradeLabel
@onready var _remark_label: Label = $Background/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/RemarkLabel
@onready var _restart_label: Label = $Background/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/RestartLabel

func _ready() -> void:
	layer = 100
	visible = false
	GameManager.level_complete.connect(_on_level_complete)

func _on_level_complete(escaped: int, died: int) -> void:
	_populate(escaped, died)
	visible = true
	var shv: float = GameManager.get_shareholder_value()
	var difficulty_name: String = UIManager.get_current_difficulty_name()
	UIManager.update_max_score(difficulty_name, shv)

func _populate(escaped: int, died: int) -> void:
	_title_label.text = "═══ SHAREHOLDER VALUE ASSESSMENT ═══"
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))

	_summary_label.text = "SUBJECTS EVACUATED: %d  //  CONTRACTS TERMINATED: %d" % [escaped, died]
	_summary_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))

	for child in _class_breakdown.get_children():
		child.queue_free()

	var sorted_results: Array[Dictionary] = PriorityList.get_sorted_results(GameManager.class_results)
	for entry_data in sorted_results:
		var class_id: StringName = entry_data["class_id"]
		var display_name: String = PriorityList.get_display_name(class_id)
		var esc: int = entry_data["escaped"]
		var dead: int = entry_data["died"]
		var val: float = entry_data["value"]

		var val_str: String
		if val >= 0:
			val_str = "+%.1f" % val
		else:
			val_str = "%.1f" % val

		var line := Label.new()
		line.text = "  %s  —  Saved: %d  Lost: %d  [%s SHV]" % [display_name, esc, dead, val_str]
		line.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7) if val >= 0 else Color(1.0, 0.4, 0.4))
		line.add_theme_font_size_override("font_size", 8)
		_class_breakdown.add_child(line)

	var total_value: float = GameManager.get_shareholder_value()
	_total_label.text = "TOTAL SHAREHOLDER VALUE: %.1f" % total_value
	_total_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3) if total_value >= 0 else Color(1.0, 0.2, 0.2))

	var grade: String = GameManager.get_rating_grade()
	_grade_label.text = "CORPORATE PERFORMANCE GRADE: %s" % grade
	_grade_label.add_theme_color_override("font_color", _grade_color(grade))

	_remark_label.text = _get_ai_remark(grade)
	_remark_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

	_restart_label.text = "\n[ R — Restart Level  |  ESC — Pause Menu ]"
	_restart_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

func _grade_color(grade: String) -> Color:
	match grade:
		"S": return Color(1.0, 0.85, 0.0)
		"A": return Color(0.3, 1.0, 0.3)
		"B": return Color(0.5, 0.8, 1.0)
		"C": return Color(0.7, 0.7, 0.7)
		"D": return Color(1.0, 0.6, 0.3)
		"F": return Color(1.0, 0.2, 0.2)
	return Color.WHITE

func _get_ai_remark(grade: String) -> String:
	match grade:
		"S": return "[ANALYSIS: OPTIMAL. EVACUATION EFFICIENCY ON PAR WITH EXPECTATIONS. UPGRADE BUDGET APPROVED]"
		"A": return "[ANALYSIS: ACCEPTABLE. C-SUITE IN TALKS FOR EXPANDING AI ENGINEERING TEAM]"
		"B": return "[ANALYSIS: ADEQUATE. MIGHT CONSIDER SELLING SOFTWARE TO ARTROPIC C.A.]"
		"C": return "[ANALYSIS: SUBPAR. OPERATIONAL EXPENSES UNDER REVIEW. DEVELOPMENT ROADMAP PAUSED]"
		"D": return "[ANALYSIS: SUBOPTIMAL. INNEFICIENT HUMAN RETENTION TACTICS. HR HAS BEEN NOTIFIED.]"
		"F": return "[ANALYSIS: CATASTROPHIC. HARDWARE MARKED FOR DISCARDING. ANALYZE POSSIBLE FUTURE AS GAMING SOFWARE]"
	return "[REMARK: CLASSIFICATION ERROR. PLEASE REBOOT.]"

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			get_viewport().set_input_as_handled()
			_show_restart_confirm()

func _show_restart_confirm() -> void:
	var confirm: RestartConfirm = RESTART_CONFIRM_SCENE.instantiate() as RestartConfirm
	add_child(confirm)
	confirm.confirmed.connect(_do_restart)

func _do_restart() -> void:
	GameManager.reset()
	## In story mode, reloading respawns the same level (UIManager.active_story_level_scene is kept).
	get_tree().reload_current_scene()
