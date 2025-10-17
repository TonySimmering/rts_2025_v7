extends Node3D

@onready var info_label = $CanvasLayer/InfoLabel

func _ready():
	info_label = get_node("CanvasLayer/InfoLabel")
	if info_label == null:
		push_error("InfoLabel not found!")
		return
	print("=== GAME SCENE LOADED ===")
	print("Is Server:", multiplayer.is_server())
	print("My ID:", multiplayer.get_unique_id())
	print("Connected Players:", NetworkManager.players)
	
	update_info()

func _process(_delta):
	if Input.is_action_just_pressed("ui_cancel"):
		print("Returning to menu...")
		NetworkManager.disconnect_from_game()
		get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

func update_info():
	var text = "GAME RUNNING\n\n"
	text += "Server: " + str(multiplayer.is_server()) + "\n"
	text += "My ID: " + str(multiplayer.get_unique_id()) + "\n"
	text += "Players connected: " + str(NetworkManager.get_player_count()) + "\n\n"
	text += "Press ESC to return to menu"
	info_label.text = text
