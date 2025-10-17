extends Control

@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_window: Window = %SettingsWindow
@onready var settings_back_button: Button = %SettingsBackButton

func _ready() -> void:
    host_button.pressed.connect(_on_host_game_pressed)
    join_button.pressed.connect(_on_join_game_pressed)
    settings_button.pressed.connect(_on_settings_pressed)
    quit_button.pressed.connect(_on_quit_pressed)
    settings_back_button.pressed.connect(_on_settings_back_pressed)

func _on_host_game_pressed() -> void:
    get_tree().set_meta("is_host", true)
    get_tree().change_scene_to_file("res://Lobby.tscn")

func _on_join_game_pressed() -> void:
    get_tree().set_meta("is_host", false)
    get_tree().change_scene_to_file("res://JoinMenu.tscn")

func _on_settings_pressed() -> void:
    settings_window.popup_centered()

func _on_settings_back_pressed() -> void:
    settings_window.hide()

func _on_quit_pressed() -> void:
    get_tree().quit()
