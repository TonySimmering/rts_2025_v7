extends PanelContainer

# Command panel UI for issuing commands to selected units

# References
@onready var command_label: Label = $VBoxContainer/CommandLabel
@onready var buttons_container: GridContainer = $VBoxContainer/ButtonsGrid
@onready var build_house_button: Button = $VBoxContainer/ButtonsGrid/BuildHouseButton
@onready var build_barracks_button: Button = $VBoxContainer/ButtonsGrid/BuildBarracksButton
@onready var build_town_center_button: Button = $VBoxContainer/ButtonsGrid/BuildTownCenterButton

# State
var selected_units: Array = []
var building_placement_manager: BuildingPlacementManager = null

# Building costs (sync with BuildingPlacementManager)
const BUILDING_COSTS = {
	"town_center": {"wood": 400, "gold": 200},
	"house": {"wood": 50},
	"barracks": {"wood": 150, "gold": 50}
}

func _ready():
	visible = false

	# Set mouse filter to prevent clicks from passing through
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Connect button signals
	if build_house_button:
		build_house_button.pressed.connect(_on_build_house_pressed)
		build_house_button.custom_minimum_size = Vector2(150, 40)

	if build_barracks_button:
		build_barracks_button.pressed.connect(_on_build_barracks_pressed)
		build_barracks_button.custom_minimum_size = Vector2(150, 40)

	if build_town_center_button:
		build_town_center_button.pressed.connect(_on_build_town_center_pressed)
		build_town_center_button.custom_minimum_size = Vector2(150, 40)

	# Setup grid
	if buttons_container:
		buttons_container.columns = 2

func set_building_placement_manager(manager: BuildingPlacementManager):
	"""Set reference to building placement manager"""
	building_placement_manager = manager

func show_units(units: Array):
	"""Display UI for the given units"""
	if not units or units.is_empty():
		hide_ui()
		return

	selected_units = units

	# Check if any of the units are workers
	var has_workers = false
	for unit in units:
		if is_instance_valid(unit) and unit.is_in_group("worker"):
			has_workers = true
			break

	if not has_workers:
		hide_ui()
		return

	# Update UI
	command_label.text = "Worker Commands (%d selected)" % units.size()

	# Show building buttons
	update_buttons()

	visible = true

func hide_ui():
	"""Hide the command UI"""
	selected_units.clear()
	visible = false

func update_buttons():
	"""Update button states based on resources"""
	var player_id = multiplayer.get_unique_id()
	var resources = ResourceManager.get_player_resources(player_id)

	# Update House button
	if build_house_button:
		var house_cost = BUILDING_COSTS["house"]
		var can_afford_house = ResourceManager.can_afford(player_id, house_cost)
		build_house_button.disabled = not can_afford_house

		var wood_cost = house_cost.get("wood", 0)
		if can_afford_house:
			build_house_button.text = "Build House\n(🪵%d)" % wood_cost
		else:
			var current_wood = resources.get("wood", 0)
			var needed = wood_cost - current_wood
			build_house_button.text = "Build House\n(🪵%d) Need %d" % [wood_cost, needed]

	# Update Barracks button
	if build_barracks_button:
		var barracks_cost = BUILDING_COSTS["barracks"]
		var can_afford_barracks = ResourceManager.can_afford(player_id, barracks_cost)
		build_barracks_button.disabled = not can_afford_barracks

		var wood_cost = barracks_cost.get("wood", 0)
		var gold_cost = barracks_cost.get("gold", 0)
		if can_afford_barracks:
			build_barracks_button.text = "Build Barracks\n(🪵%d 💰%d)" % [wood_cost, gold_cost]
		else:
			build_barracks_button.text = "Build Barracks\n(🪵%d 💰%d) ❌" % [wood_cost, gold_cost]

	# Update Town Center button (expensive)
	if build_town_center_button:
		var tc_cost = BUILDING_COSTS["town_center"]
		var can_afford_tc = ResourceManager.can_afford(player_id, tc_cost)
		build_town_center_button.disabled = not can_afford_tc

		var wood_cost = tc_cost.get("wood", 0)
		var gold_cost = tc_cost.get("gold", 0)
		if can_afford_tc:
			build_town_center_button.text = "Build Town Center\n(🪵%d 💰%d)" % [wood_cost, gold_cost]
		else:
			build_town_center_button.text = "Build Town Center\n(🪵%d 💰%d) ❌" % [wood_cost, gold_cost]

func _on_build_house_pressed():
	"""Called when Build House button is pressed"""
	print("Build House button pressed")
	start_building_placement("house")

func _on_build_barracks_pressed():
	"""Called when Build Barracks button is pressed"""
	print("Build Barracks button pressed")
	start_building_placement("barracks")

func _on_build_town_center_pressed():
	"""Called when Build Town Center button is pressed"""
	print("Build Town Center button pressed")
	start_building_placement("town_center")

func start_building_placement(building_type: String):
	"""Start building placement mode"""
	if not building_placement_manager:
		print("❌ Building placement manager not set!")
		return

	# Filter only workers from selected units
	var workers = []
	for unit in selected_units:
		if is_instance_valid(unit) and unit.is_in_group("worker"):
			workers.append(unit)

	if workers.is_empty():
		print("❌ No workers selected!")
		return

	building_placement_manager.start_placement_mode(building_type, workers)

	# Hide command UI during placement
	# It will show again when placement ends
	hide_ui()

func _process(_delta):
	# Update button affordability continuously
	if visible and selected_units.size() > 0:
		update_buttons()
