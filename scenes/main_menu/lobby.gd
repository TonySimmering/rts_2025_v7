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
	NetworkManager.player_ready_changed.connect(_on_player_ready_changed)
	
	start_button.visible = multiplayer.is_server()
	start_button.disabled = true
	
	# Display host IP if we're the server
	if multiplayer.is_server():
		var local_ip = get_local_ip()
		status_label.text = "Host IP: " + local_ip + " | Port: 7777"
	else:
		status_label.text = "Players: " + str(NetworkManager.get_player_count()) + "/" + str(NetworkManager.MAX_CLIENTS)
	
        print("Lobby ready. Is server: ", multiplayer.is_server())
        print("Initial players: ", NetworkManager.players)

        update_player_list()
        _update_ready_button_label()
        if multiplayer.is_server():
                check_all_ready()

func get_local_ip() -> String:
	"""Get the local network IP address"""
	var addresses = IP.get_local_addresses()
	
	# Find the first non-localhost IPv4 address
	for addr in addresses:
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	
	# Fallback
	return "Unknown (check ipconfig/ifconfig)"

func _on_ready_pressed():
        var my_id = multiplayer.get_unique_id()
        var is_ready = not NetworkManager.players[my_id].get("ready", false)

        print("Ready button pressed. My ID: ", my_id, " Setting ready to: ", is_ready)

        NetworkManager.players[my_id]["ready"] = is_ready
        NetworkManager.rpc("set_player_ready", my_id, is_ready)

        ready_button.disabled = true
        update_player_list()

        if multiplayer.is_server():
                check_all_ready()

        await get_tree().process_frame
        _update_ready_button_label()
        ready_button.disabled = false

func _on_start_pressed():
	print("Start button pressed!")
	if multiplayer.is_server() and NetworkManager.are_all_players_ready():
		print("All players ready, starting game...")
		
		# Generate seed on server
		var seed = NetworkManager.generate_game_seed()
		
		# Send seed to all clients
		NetworkManager.sync_game_seed.rpc(seed)
		
		# Small delay to ensure seed arrives before scene loads
		await get_tree().create_timer(0.1).timeout
		
		load_game.rpc()
	else:
		print("Cannot start - Not all ready or not server")
		print("Is server: ", multiplayer.is_server())
		print("All ready: ", NetworkManager.are_all_players_ready())

@rpc("authority", "call_local", "reliable")
func load_game():
	print("Loading game scene...")
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")

func _on_back_pressed():
	if multiplayer.is_server():
		print("Host terminating session...")
		# Notify all clients that server is closing
		kick_all_clients.rpc()
		# Small delay to ensure RPC arrives
		await get_tree().create_timer(0.1).timeout
	else:
		print("Client leaving game...")
	
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

@rpc("authority", "call_local", "reliable")
func kick_all_clients():
	"""Called by host to notify clients the session is ending"""
	if not multiplayer.is_server():
		print("Host closed the session")
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

func _on_player_ready_changed(peer_id: int, is_ready: bool):
        print("Lobby: Player ", peer_id, " ready changed to ", is_ready)
        update_player_list()
        if multiplayer.is_server():
                check_all_ready()

        if peer_id == multiplayer.get_unique_id():
                _update_ready_button_label()

func check_all_ready():
        var all_ready = NetworkManager.are_all_players_ready()
        print("Checking if all ready: ", all_ready)
        print("Current players state: ", NetworkManager.players)
        start_button.disabled = not all_ready
        print("Start button disabled: ", start_button.disabled)

        if multiplayer.is_server():
                var ready_count = 0
                for player in NetworkManager.players.values():
                        if player.get("ready", false):
                                ready_count += 1
                status_label.text = "Ready: " + str(ready_count) + "/" + str(NetworkManager.players.size())

func update_player_list():
	var text = "[b]Players in Lobby:[/b]\n\n"
	for peer_id in NetworkManager.players:
		var player = NetworkManager.players[peer_id]
		var ready_icon = "✓" if player.get("ready", false) else "✗"
		var host_tag = " [color=yellow](Host)[/color]" if peer_id == 1 else ""
		var color = "green" if player.get("ready", false) else "white"
		text += "[color=" + color + "]" + ready_icon + " " + player.name + host_tag + "[/color]\n"
	
	player_list.text = text
	
        if not multiplayer.is_server():
                status_label.text = "Players: " + str(NetworkManager.get_player_count()) + "/" + str(NetworkManager.MAX_CLIENTS)

func _update_ready_button_label():
        var my_id = multiplayer.get_unique_id()
        var my_state = NetworkManager.players.get(my_id, {"ready": false})
        var is_ready = my_state.get("ready", false)
        ready_button.text = "Not Ready" if is_ready else "Ready"
