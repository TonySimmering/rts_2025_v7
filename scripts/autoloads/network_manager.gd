extends Node

signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_started
signal connection_failed
signal connection_succeeded

const DEFAULT_PORT = 7777
const MAX_CLIENTS = 8

var peer: ENetMultiplayerPeer
var players: Dictionary = {}
var pending_player_name: String = ""

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(player_name: String, port: int = DEFAULT_PORT) -> bool:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		push_error("Failed to create server")
		return false
	multiplayer.multiplayer_peer = peer
	var host_info = {"name": player_name, "id": 1, "ready": false}
	players[1] = host_info
	print("Server started on port ", port)
	server_started.emit()
	return true

func join_game(player_name: String, ip_address: String, port: int = DEFAULT_PORT) -> bool:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip_address, port)
	if error != OK:
		push_error("Failed to create client")
		return false
	multiplayer.multiplayer_peer = peer
	pending_player_name = player_name
	print("Attempting to connect to ", ip_address, ":", port)
	return true

func disconnect_from_game():
	if peer:
		peer.close()
	players.clear()
	multiplayer.multiplayer_peer = null

func _on_player_connected(id: int):
	print("Player connected: ", id)
	if multiplayer.is_server():
		rpc_id(id, "register_player", players[1])

func _on_player_disconnected(id: int):
	print("Player disconnected: ", id)
	if players.has(id):
		players.erase(id)
	player_disconnected.emit(id)

func _on_connected_to_server():
	print("Successfully connected to server")
	var my_id = multiplayer.get_unique_id()
	var my_info = {"name": pending_player_name, "id": my_id, "ready": false}
	players[my_id] = my_info
	rpc_id(1, "register_player", my_info)
	connection_succeeded.emit()

func _on_connection_failed():
	print("Connection failed")
	peer = null
	connection_failed.emit()

func _on_server_disconnected():
	print("Server disconnected")
	disconnect_from_game()

@rpc("any_peer", "reliable")
func register_player(player_info: Dictionary):
	var sender_id = multiplayer.get_remote_sender_id()
	var player_id = player_info.get("id", sender_id)
	
	print("Registering player ID: ", player_id, " Name: ", player_info.get("name", "Unknown"))
	
	players[player_id] = player_info
	player_connected.emit(player_id, player_info)
	
	if multiplayer.is_server():
		for peer_id in multiplayer.get_peers():
			if peer_id != player_id:
				rpc_id(peer_id, "register_player", player_info)
		
		for existing_id in players:
			if existing_id != player_id:
				rpc_id(player_id, "register_player", players[existing_id])

@rpc("any_peer", "call_local", "reliable")
func set_player_ready(peer_id: int, is_ready: bool):
	if players.has(peer_id):
		players[peer_id]["ready"] = is_ready
		print("Player ", peer_id, " ready status: ", is_ready)

func are_all_players_ready() -> bool:
	for player in players.values():
		if not player.ready:
			return false
	return players.size() > 0

func get_player_count() -> int:
	return players.size()
