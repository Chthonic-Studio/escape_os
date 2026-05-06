class_name StoryData
extends Resource

## Defines a story campaign with a list of ordered levels.
## Create .tres instances in Resources/Stories/ and assign levels.

@export_category("Identity")
@export var story_name: String = "Untitled Story"
@export_multiline var story_description: String = "No description provided."
## Short subtitle shown in the selection screen.
@export var story_subtitle: String = ""
## Unique identifier used for progress tracking.
@export var story_id: StringName = &"story_unnamed"

@export_category("Levels")
## Ordered list of StoryLevelData resources. Level 0 is always unlocked.
@export var levels: Array[StoryLevelData] = []
