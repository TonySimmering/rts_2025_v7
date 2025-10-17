extends Node3D

@onready var info_label = $CanvasLayer/InfoLabel

# Preload camera scene
const CAMERA_RIG_SCENE = preload("res://scenes/camera/camera_rig.tscn")

var local_camera: Node3D = null

func _ready():
	print("=== GAME SCENE LOADED ===")
	print("Is Server:", multiplayer.is_server())
	print("My ID:", multiplayer.get_unique_id())
	print("Connected Players:", NetworkManager.players)
	
	# Spawn local camera for this player (NOT networked!)
	spawn_local_camera()
	
	# Connect to network signals to update when players join/leave
	NetworkManager.player_connected.connect(_on_player_joined)
	NetworkManager.player_disconnected.connect(_on_player_left)
	
	update_info()

func spawn_local_camera():
	# Create camera instance locally (not synced across network)
	local_camera = CAMERA_RIG_SCENE.instantiate()
	add_child(local_camera)
	print("Local camera spawned for player ", multiplayer.get_unique_id())

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
	text += "\nWASD/Arrows: Pan | Q/E: Rotate | Scroll: Zoom"
	info_label.text = text
