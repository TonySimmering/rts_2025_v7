extends Node3D

@onready var info_label = $CanvasLayer/InfoLabel

func _ready():
	print("=== GAME SCENE LOADED ===")
	print("Is Server:", multiplayer.is_server())
	print("My ID:", multiplayer.get_unique_id())
	print("Connected Players:", NetworkManager.players)
	
	# Connect to network signals to update when players join/leave
	NetworkManager.player_connected.connect(_on_player_joined)
	NetworkManager.player_disconnected.connect(_on_player_left)
	
	update_info()

func _process(_delta):
	if Input.is_action_just_pressed("ui_cancel"):
		print("Returning to menu...")
		NetworkManager.disconnect_from_game()
		get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

func _on_player_joined(peer_id: int, player_info: Dictionary):
	print("Game scene notified: Player joined - ", peer_id)
	update_info()

func _on_player_left(peer_id: int):
	print("Game scene notified: Player left - ", peer_id)
	update_info()

func update_info():
	var text = "GAME RUNNING\n\n"
	text += "Server: " + str(multiplayer.is_server()) + "\n"
	text += "My ID: " + str(multiplayer.get_unique_id()) + "\n"
	text += "Players connected: " + str(NetworkManager.get_player_count()) + "\n"
	
	# List all players
	text += "\nPlayer List:\n"
	for peer_id in NetworkManager.players:
		var player = NetworkManager.players[peer_id]
		text += "  - " + player.name + " (ID: " + str(peer_id) + ")\n"
	
	text += "\nPress ESC to return to menu"
	info_label.text = text
