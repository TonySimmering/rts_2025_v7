extends Control

@onready var host_button = $VBoxContainer/HostButton
@onready var join_button = $VBoxContainer/JoinButton

func _ready():
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	
	NetworkManager.server_started.connect(_on_server_started)

func _on_host_pressed():
	print("Hosting game...")
	NetworkManager.host_game("Host Player")

func _on_join_pressed():
	print("Going to join menu...")
	get_tree().change_scene_to_file("res://scenes/main_menu/join_menu.tscn")

func _on_server_started():
	print("Server started! Going to lobby...")
	get_tree().change_scene_to_file("res://scenes/main_menu/lobby.tscn")
