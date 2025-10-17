extends Control

@onready var player_list: RichTextLabel = $VBoxContainer/PlayerList
@onready var ready_button: Button = $VBoxContainer/HBoxContainer/ReadyButton
@onready var start_button: Button = $VBoxContainer/HBoxContainer/StartButton
@onready var back_button: Button = $VBoxContainer/BackButton
@onready var status_label: Label = $StatusLabel

func _ready():
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	
	start_button.visible = multiplayer.is_server()
	start_button.disabled = true
	
	print("Lobby ready. Is server: ", multiplayer.is_server())
	print("Initial players: ", NetworkManager.players)
	
	update_player_list()

func _on_ready_pressed():
	var my_id = multiplayer.get_unique_id()
	var is_ready = not NetworkManager.players[my_id].get("ready", false)
	
	print("Ready button pressed. My ID: ", my_id, " Setting ready to: ", is_ready)
	
	NetworkManager.players[my_id]["ready"] = is_ready
	NetworkManager.rpc("set_player_ready", my_id, is_ready)
	
	ready_button.text = "Not Ready" if is_ready else "Ready"
	update_player_list()
	
	if multiplayer.is_server():
		check_all_ready()

func _on_start_pressed():
	print("Start button pressed!")
	if multiplayer.is_server() and NetworkManager.are_all_players_ready():
		print("All players ready, starting game...")
		rpc("load_game")
	else:
		print("Cannot start - Not all ready or not server")
		print("Is server: ", multiplayer.is_server())
		print("All ready: ", NetworkManager.are_all_players_ready())

@rpc("authority", "call_local", "reliable")
func load_game():
	print("Loading game scene...")
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")

func _on_back_pressed():
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

func _on_player_connected(peer_id: int, player_info: Dictionary):
	print("Lobby: Player connected - ", peer_id)
	update_player_list()
	if multiplayer.is_server():
		check_all_ready()

func _on_player_disconnected(peer_id: int):
	print("Lobby: Player disconnected - ", peer_id)
	update_player_list()
	if multiplayer.is_server():
		check_all_ready()

func check_all_ready():
	var all_ready = NetworkManager.are_all_players_ready()
	print("Checking if all ready: ", all_ready)
	print("Current players state: ", NetworkManager.players)
	start_button.disabled = not all_ready
	print("Start button disabled: ", start_button.disabled)

func update_player_list():
	var text = "[b]Players in Lobby:[/b]\n\n"
	for peer_id in NetworkManager.players:
		var player = NetworkManager.players[peer_id]
		var ready_icon = "✓" if player.get("ready", false) else "✗"
		var host_tag = " [color=yellow](Host)[/color]" if peer_id == 1 else ""
		var color = "green" if player.get("ready", false) else "white"
		text += "[color=" + color + "]" + ready_icon + " " + player.name + host_tag + "[/color]\n"
	
	player_list.text = text
	status_label.text = "Players: " + str(NetworkManager.get_player_count()) + "/" + str(NetworkManager.MAX_CLIENTS)
