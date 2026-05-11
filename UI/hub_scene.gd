class_name HubScene
extends Control

## Between-run hub scene (OS Interface).
## Reads RunData.shv_earned for spendable currency.
## Shows: permanent upgrades panel, story modules log, next-run corruption preview.
## All UI is built programmatically so no matching .tscn is required.

var _shv_label: Label = null
var _upgrades_list: VBoxContainer = null
var _story_log: VBoxContainer = null
var _corruption_preview: VBoxContainer = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh_ui()

func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_vbox)

	## SHV header.
	_shv_label = Label.new()
	_shv_label.text = "SHV: 0.0"
	root_vbox.add_child(_shv_label)

	## Upgrades.
	root_vbox.add_child(_make_label("── UPGRADES ──"))
	_upgrades_list = VBoxContainer.new()
	root_vbox.add_child(_upgrades_list)

	## Story log.
	root_vbox.add_child(_make_label("── STORY LOG ──"))
	_story_log = VBoxContainer.new()
	root_vbox.add_child(_story_log)

	## Corruption preview.
	root_vbox.add_child(_make_label("── CORRUPTION FORECAST ──"))
	_corruption_preview = VBoxContainer.new()
	root_vbox.add_child(_corruption_preview)

	## Start run button.
	var btn := Button.new()
	btn.text = "START RUN"
	btn.pressed.connect(_on_start_run)
	root_vbox.add_child(btn)

func _make_label(txt: String) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	return lbl

func _refresh_ui() -> void:
	var meta: MetaProgress = SaveManager.load_meta_progress()
	var run_data: RunData = RunManager.current_run

	## SHV currency.
	if _shv_label:
		var shv: float = meta.total_shv_banked if meta else 0.0
		_shv_label.text = "SHV: %.1f" % shv

	## Permanent upgrades.
	if _upgrades_list and meta:
		for child in _upgrades_list.get_children():
			child.queue_free()
		for upgrade in meta.purchased_upgrades:
			if upgrade is PermanentUpgrade:
				var lbl := Label.new()
				lbl.text = "[%s] %s" % [upgrade.upgrade_id, upgrade.effect_type]
				_upgrades_list.add_child(lbl)

	## Story modules log.
	if _story_log and meta:
		for child in _story_log.get_children():
			child.queue_free()
		for mod in meta.unlocked_modules:
			if mod is StoryModule:
				var lbl := Label.new()
				lbl.text = "[%s] %s" % [mod.module_id, mod.log_text.left(60)]
				_story_log.add_child(lbl)

	## Corruption preview — show mutators that will be active in the next run.
	if _corruption_preview:
		for child in _corruption_preview.get_children():
			child.queue_free()
		var next_stability: int = RunManager.next_stability_level()
		for mutator in RunManager.all_mutators:
			if mutator is CorruptionMutator:
				var lbl := Label.new()
				if mutator.stability_tier >= next_stability:
					lbl.text = "[ACTIVE] %s" % mutator.display_name
					lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2, 1.0))
				else:
					lbl.text = "[ off ] %s" % mutator.display_name
					lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.6))
				_corruption_preview.add_child(lbl)

func _on_start_run() -> void:
	RunManager.start_run()
