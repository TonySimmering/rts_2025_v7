extends Node3D

@onready var debug_label: Label = $CanvasLayer/DebugLabel

func _ready():
	print("Game scene loaded!")
	print("Is server: ", multiplayer.is_server())
	print("My ID: ", multiplayer.get_unique_id())
	print("Players: ", NetworkManager.players)
	
	update_debug_info()

func _process(_delta):
	if Input.is_action_just_pressed("ui_cancel"):
		return_to_menu()

func update_debug_info():
	var text = "Game Running\n"
	text += "Server: " + str(multiplayer.is_server()) + "\n"
	text += "ID: " + str(multiplayer.get_unique_id()) + "\n"
	text += "Players: " + str(NetworkManager.get_player_count()) + "\n"
	text += "\nPress ESC to return to menu"
	debug_label.text = text

func return_to_menu():
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
