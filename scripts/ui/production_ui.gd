extends PanelContainer

# References
@onready var building_name_label: Label = $VBoxContainer/BuildingName
@onready var production_queue_container: HBoxContainer = $VBoxContainer/ProductionQueue
@onready var buttons_container: VBoxContainer = $VBoxContainer/Buttons
@onready var train_worker_button: Button = $VBoxContainer/Buttons/TrainWorkerButton
@onready var rally_button: Button = $VBoxContainer/Buttons/RallyButton

# State
var selected_building: Node = null
var rally_mode_active: bool = false

# Signal to notify selection manager
signal rally_mode_activated(building: Node)
signal rally_mode_deactivated()

func _ready():
	visible = false

	# Set mouse filter to prevent clicks from passing through
	mouse_filter = Control.MOUSE_FILTER_STOP

	train_worker_button.pressed.connect(_on_train_worker_pressed)
	rally_button.pressed.connect(_on_rally_button_pressed)

	# Set up button styling
	train_worker_button.custom_minimum_size = Vector2(200, 40)
	rally_button.custom_minimum_size = Vector2(200, 40)

func show_building(building: Node):
	"""Display UI for the given building"""
	print("\n=== SHOW_BUILDING CALLED ===")
	print("Building: ", building)
	
	if not building or not building.is_in_group("buildings"):
		print("❌ Not a valid building!")
		hide_ui()
		return
	
	print("✓ Valid building: ", building.building_name)
	
	selected_building = building
	
	# Connect signals
	if building.has_signal("production_queue_changed"):
		if not building.production_queue_changed.is_connected(_on_production_queue_changed):
			building.production_queue_changed.connect(_on_production_queue_changed)
			print("✓ Connected to production_queue_changed signal")
	
	# Update UI
	building_name_label.text = building.building_name if building.has_method("get") else "Building"
	
	# Show appropriate buttons based on building type
	update_buttons()
	update_production_queue()
	
	visible = true
	print("✓ UI now visible")
	print("=== SHOW_BUILDING COMPLETE ===\n")

func hide_ui():
	"""Hide the production UI"""
	print("\n=== HIDE_UI CALLED ===")
	print("Stack trace:")
	print(get_stack())
	
	# Disconnect signals
	if selected_building and is_instance_valid(selected_building):
		if selected_building.has_signal("production_queue_changed"):
			if selected_building.production_queue_changed.is_connected(_on_production_queue_changed):
				selected_building.production_queue_changed.disconnect(_on_production_queue_changed)
	
	selected_building = null
	visible = false
	print("✓ UI now hidden")
	print("=== HIDE_UI COMPLETE ===\n")

func update_buttons():
	"""Update button states based on building type and resources"""
	if not selected_building or not is_instance_valid(selected_building):
		print("⚠ update_buttons: No valid building")
		return

	# Show/hide buttons based on building type
	if selected_building.building_name == "Town Center":
		train_worker_button.visible = true
		rally_button.visible = true

		# Update rally button text based on mode
		if rally_mode_active:
			rally_button.text = "Rally (Click Map)"
		else:
			rally_button.text = "Set Rally Point"

		# Update button state based on affordability
		if selected_building.has_method("can_train_worker"):
			var can_train = selected_building.can_train_worker()
			train_worker_button.disabled = not can_train

			# Update button text with cost
			var cost = selected_building.WORKER_COST
			var gold_cost = cost.get("gold", 0)
			train_worker_button.text = "Train Worker (💰%d)" % gold_cost

			# Show why button is disabled
			if not can_train:
				var player_id = multiplayer.get_unique_id()
				var resources = ResourceManager.get_player_resources(player_id)
				var current_gold = resources.get("gold", 0)

				if current_gold < gold_cost:
					train_worker_button.text = "Train Worker (💰%d) - Need %d more gold" % [gold_cost, gold_cost - current_gold]
				elif selected_building.production_queue.size() >= selected_building.MAX_QUEUE_SIZE:
					train_worker_button.text = "Train Worker (💰%d) - Queue Full" % gold_cost
	elif selected_building.building_name == "Barracks":
		train_worker_button.visible = false
		rally_button.visible = true

		# Update rally button text based on mode
		if rally_mode_active:
			rally_button.text = "Rally (Click Map)"
		else:
			rally_button.text = "Set Rally Point"
	else:
		train_worker_button.visible = false
		rally_button.visible = false

func update_production_queue():
	"""Update the production queue display"""
	# Clear existing queue display
	for child in production_queue_container.get_children():
		child.queue_free()
	
	if not selected_building or not is_instance_valid(selected_building):
		return
	
	if not selected_building.has_method("get_queue_size"):
		return
	
	var queue_size = selected_building.get_queue_size()
	
	if queue_size == 0:
		var no_queue_label = Label.new()
		no_queue_label.text = "No units in production"
		no_queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		production_queue_container.add_child(no_queue_label)
		return
	
	# Show production queue
	for i in range(queue_size):
		var queue_item = selected_building.production_queue[i]
		var progress = queue_item.progress / queue_item.total_time

		# Create container for this queue item (vertical within horizontal queue)
		var item_container = VBoxContainer.new()
		item_container.custom_minimum_size = Vector2(120, 0)
		
		# Unit name and progress text
		var item_label = Label.new()
		if i == 0:
			item_label.text = "Training: Worker (%d%%)" % int(progress * 100)
		else:
			item_label.text = "Queued: Worker"
		item_container.add_child(item_label)
		
		# Progress bar (only for first item)
		if i == 0:
			var progress_bar = ProgressBar.new()
			progress_bar.min_value = 0
			progress_bar.max_value = 1.0
			progress_bar.value = progress
			progress_bar.show_percentage = true
			progress_bar.custom_minimum_size = Vector2(100, 20)
			item_container.add_child(progress_bar)
		
		production_queue_container.add_child(item_container)

func _on_production_queue_changed(_queue: Array):
	"""Called when building's production queue changes"""
	update_production_queue()
	update_buttons()

func _on_train_worker_pressed():
	"""Called when Train Worker button is pressed"""
	print("=== TRAIN WORKER BUTTON PRESSED ===")
	
	if not selected_building or not is_instance_valid(selected_building):
		print("❌ No valid building selected!")
		return
	
	print("✓ Building valid: ", selected_building.building_name)
	
	if not selected_building.has_method("train_worker"):
		print("❌ Building doesn't have train_worker method!")
		return
	
	print("✓ Building has train_worker method")
	
	var player_id = multiplayer.get_unique_id()
	var resources = ResourceManager.get_player_resources(player_id)
	print("Current resources: ", resources)
	
	# Only the server can train units
	if not multiplayer.is_server():
		print("⚠ Client - sending RPC to server")
		request_train_worker.rpc_id(1, selected_building.get_path())
		return
	
	print("✓ Server - calling train_worker directly")
	selected_building.train_worker()
	
	# Update UI immediately
	update_buttons()
	update_production_queue()
	print("=== TRAIN WORKER REQUEST COMPLETE ===\n")

@rpc("any_peer", "call_remote", "reliable")
func request_train_worker(building_path: NodePath):
	"""Server receives train request from client"""
	print("=== SERVER RECEIVED TRAIN REQUEST ===")
	print("Building path: ", building_path)
	
	if not multiplayer.is_server():
		print("❌ Not server, ignoring")
		return
	
	var building = get_node_or_null(building_path)
	if not building or not is_instance_valid(building):
		print("❌ Building not found at path: ", building_path)
		return
	
	print("✓ Building found: ", building.building_name)
	
	# Verify this is the player's building
	var sender_id = multiplayer.get_remote_sender_id()
	print("Request from player: ", sender_id)
	print("Building owner: ", building.player_id)
	
	if building.player_id != sender_id:
		print("❌ Player ", sender_id, " tried to train from player ", building.player_id, "'s building!")
		return
	
	print("✓ Ownership verified, calling train_worker()")
	building.train_worker()
	print("=== TRAIN REQUEST COMPLETE ===\n")

func _on_rally_button_pressed():
	"""Called when Rally button is pressed"""
	print("=== RALLY BUTTON PRESSED ===")

	if not selected_building or not is_instance_valid(selected_building):
		print("❌ No valid building selected!")
		return

	# Toggle rally mode
	rally_mode_active = not rally_mode_active

	if rally_mode_active:
		print("✓ Rally mode activated - click on map to set rally point")
		rally_mode_activated.emit(selected_building)
	else:
		print("✓ Rally mode deactivated")
		rally_mode_deactivated.emit()

	update_buttons()
	print("=== RALLY BUTTON COMPLETE ===\n")

func deactivate_rally_mode():
	"""Deactivate rally mode (called by selection manager after setting point)"""
	rally_mode_active = false
	update_buttons()

func _process(_delta):
	# Update progress bars continuously
	if visible and selected_building and is_instance_valid(selected_building):
		if selected_building.has_method("get_queue_size") and selected_building.get_queue_size() > 0:
			update_production_queue()

		# Update button affordability
		update_buttons()
