extends Node

## SaveManager — autoload that handles all file I/O for the game.
##
## Implements autosave-only.  No manual save/load UI is exposed to the player.
## Three separate files are maintained:
##   user://run_save.json   — current in-progress run (RunData)
##   user://meta.json       — cross-run permanent progress (MetaProgress)
##   user://story_progress.json — story-mode chapter progress (unchanged)

const RUN_SAVE_PATH: String = "user://run_save.json"
const META_SAVE_PATH: String = "user://meta.json"

## ── Run ─────────────────────────────────────────────────────────────────────

func save_run(run: RunData) -> void:
	if run == null:
		return
	var f: FileAccess = FileAccess.open(RUN_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: failed to open %s for writing." % RUN_SAVE_PATH)
		return
	f.store_string(JSON.stringify(run.to_dict(), "\t"))
	f.close()

func load_run() -> RunData:
	if not FileAccess.file_exists(RUN_SAVE_PATH):
		return null
	var f: FileAccess = FileAccess.open(RUN_SAVE_PATH, FileAccess.READ)
	if f == null:
		return null
	var raw: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return null
	var run := RunData.new()
	run.from_dict(parsed)
	return run if run.is_active else null

func delete_run() -> void:
	if FileAccess.file_exists(RUN_SAVE_PATH):
		DirAccess.remove_absolute(RUN_SAVE_PATH)

## ── MetaProgress ─────────────────────────────────────────────────────────────

func save_meta(meta: MetaProgress) -> void:
	if meta == null:
		return
	var d: Dictionary = {
		"total_shv_banked": meta.total_shv_banked,
		"upgrade_levels": meta.upgrade_levels,
		"unlocked_modules": meta.unlocked_modules,
		"runs_completed": meta.runs_completed,
	}
	var f: FileAccess = FileAccess.open(META_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: failed to open %s for writing." % META_SAVE_PATH)
		return
	f.store_string(JSON.stringify(d, "\t"))
	f.close()

func load_meta() -> MetaProgress:
	var meta := MetaProgress.new()
	if not FileAccess.file_exists(META_SAVE_PATH):
		return meta
	var f: FileAccess = FileAccess.open(META_SAVE_PATH, FileAccess.READ)
	if f == null:
		return meta
	var raw: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return meta
	meta.total_shv_banked = float(parsed.get("total_shv_banked", 0.0))
	var ul = parsed.get("upgrade_levels", {})
	if ul is Dictionary:
		meta.upgrade_levels = ul
	var um = parsed.get("unlocked_modules", [])
	if um is Array:
		meta.unlocked_modules = Array(um, TYPE_STRING_NAME, &"", null)
	meta.runs_completed = int(parsed.get("runs_completed", 0))
	return meta
