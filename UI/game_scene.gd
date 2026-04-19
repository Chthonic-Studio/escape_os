class_name GameScene
extends Control

## Master layout orchestrator. 

@onready var game_viewport: SubViewport = $MarginContainer/HBoxContainer/VBoxContainer/SubViewportContainer/SubViewport

func _ready() -> void:
	UIManager.add_assessment_screen(self)
	UIManager.add_main_menu(self)
