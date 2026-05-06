class_name StoryLevelData
extends Resource

## Metadata for a single level inside a story campaign.
## The actual level layout lives in the referenced .tscn file.

@export_category("Identity")
@export var level_name: String = "Level 1"
@export_multiline var level_description: String = "No description provided."

@export_category("Scene")
## Path to the .tscn file that contains the level's StoryLevelController.
@export_file("*.tscn") var level_scene_path: String = ""
