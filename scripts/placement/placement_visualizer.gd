extends Node3D
class_name PlacementVisualizer

## Provides visual feedback for building placement
##
## This class handles:
## - Drawing snap guide lines between buildings
## - Highlighting snap points on nearby buildings
## - Showing grid overlay
## - Color coding for valid/invalid placement
## - Connection indicators for snapped buildings

# Visual components
var snap_line_mesh: ImmediateMesh
var snap_points_mesh: ImmediateMesh
var grid_mesh: ImmediateMesh
var connection_indicator_mesh: ImmediateMesh

# Mesh instances
var snap_line_instance: MeshInstance3D
var snap_points_instance: MeshInstance3D
var grid_instance: MeshInstance3D
var connection_indicator_instance: MeshInstance3D

# Materials
var snap_line_material: StandardMaterial3D
var snap_point_material: StandardMaterial3D
var grid_material: StandardMaterial3D
var connection_material: StandardMaterial3D
var active_snap_material: StandardMaterial3D

# Visual settings
const SNAP_LINE_WIDTH: float = 0.1
const SNAP_POINT_SIZE: float = 0.3
const GRID_LINE_WIDTH: float = 0.05
const CONNECTION_LINE_WIDTH: float = 0.15

# Colors
const SNAP_LINE_COLOR: Color = Color(0.3, 0.8, 1.0, 0.8)  # Cyan
const SNAP_POINT_COLOR: Color = Color(1.0, 1.0, 0.0, 0.6)  # Yellow
const ACTIVE_SNAP_COLOR: Color = Color(0.0, 1.0, 0.0, 0.9)  # Green
const GRID_COLOR: Color = Color(0.5, 0.5, 0.5, 0.2)  # Gray
const CONNECTION_COLOR: Color = Color(0.2, 1.0, 0.2, 0.9)  # Bright green

# State
var show_snap_lines: bool = true
var show_snap_points: bool = true
var show_grid: bool = false
var show_connections: bool = true

func _ready():
	_setup_materials()
	_setup_mesh_instances()

func _setup_materials():
	"""Create materials for visualization"""
	# Snap line material
	snap_line_material = StandardMaterial3D.new()
	snap_line_material.albedo_color = SNAP_LINE_COLOR
	snap_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	snap_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	snap_line_material.no_depth_test = true

	# Snap point material
	snap_point_material = StandardMaterial3D.new()
	snap_point_material.albedo_color = SNAP_POINT_COLOR
	snap_point_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	snap_point_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	snap_point_material.no_depth_test = true

	# Active snap material (brighter green)
	active_snap_material = StandardMaterial3D.new()
	active_snap_material.albedo_color = ACTIVE_SNAP_COLOR
	active_snap_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	active_snap_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	active_snap_material.no_depth_test = true

	# Grid material
	grid_material = StandardMaterial3D.new()
	grid_material.albedo_color = GRID_COLOR
	grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.no_depth_test = true

	# Connection material
	connection_material = StandardMaterial3D.new()
	connection_material.albedo_color = CONNECTION_COLOR
	connection_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	connection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	connection_material.no_depth_test = true

func _setup_mesh_instances():
	"""Create mesh instances for visualization"""
	# Snap lines
	snap_line_mesh = ImmediateMesh.new()
	snap_line_instance = MeshInstance3D.new()
	snap_line_instance.mesh = snap_line_mesh
	snap_line_instance.material_override = snap_line_material
	add_child(snap_line_instance)

	# Snap points
	snap_points_mesh = ImmediateMesh.new()
	snap_points_instance = MeshInstance3D.new()
	snap_points_instance.mesh = snap_points_mesh
	snap_points_instance.material_override = snap_point_material
	add_child(snap_points_instance)

	# Grid
	grid_mesh = ImmediateMesh.new()
	grid_instance = MeshInstance3D.new()
	grid_instance.mesh = grid_mesh
	grid_instance.material_override = grid_material
	add_child(grid_instance)

	# Connection indicators
	connection_indicator_mesh = ImmediateMesh.new()
	connection_indicator_instance = MeshInstance3D.new()
	connection_indicator_instance.mesh = connection_indicator_mesh
	connection_indicator_instance.material_override = connection_material
	add_child(connection_indicator_instance)

## Update visualization for current placement state
func update_visualization(
	ghost_position: Vector3,
	snap_points: Array,
	active_snap_point,
	grid_data: Dictionary
):
	# Clear previous visualizations
	clear_all()

	# Draw snap points
	if show_snap_points and not snap_points.is_empty():
		_draw_snap_points(snap_points, active_snap_point)

	# Draw snap lines
	if show_snap_lines and active_snap_point != null:
		_draw_snap_line(ghost_position, active_snap_point)

	# Draw grid
	if show_grid and not grid_data.is_empty():
		_draw_grid(grid_data)

	# Draw connection indicator
	if show_connections and active_snap_point != null:
		_draw_connection_indicator(ghost_position, active_snap_point)

## Draw snap points as small spheres
func _draw_snap_points(snap_points: Array, active_snap_point):
	snap_points_mesh.clear_surfaces()

	for snap_point in snap_points:
		var is_active = (snap_point == active_snap_point)
		var point_size = SNAP_POINT_SIZE * (1.5 if is_active else 1.0)
		var color = ACTIVE_SNAP_COLOR if is_active else SNAP_POINT_COLOR

		# Draw a small cube at snap point
		_draw_cube_at_position(snap_points_mesh, snap_point.position, point_size, color)

## Draw a line from ghost to active snap point
func _draw_snap_line(ghost_position: Vector3, snap_point):
	snap_line_mesh.clear_surfaces()

	if snap_point == null:
		return

	# Draw line from ghost center to snap point
	snap_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	snap_line_mesh.surface_add_vertex(ghost_position + Vector3(0, 0.5, 0))  # Slightly above ground
	snap_line_mesh.surface_add_vertex(snap_point.position + Vector3(0, 0.5, 0))
	snap_line_mesh.surface_end()

## Draw grid overlay
func _draw_grid(grid_data: Dictionary):
	grid_mesh.clear_surfaces()

	if not grid_data.has("lines"):
		return

	var lines = grid_data.lines
	if lines.is_empty():
		return

	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for line_data in lines:
		grid_mesh.surface_add_vertex(line_data.start)
		grid_mesh.surface_add_vertex(line_data.end)

	grid_mesh.surface_end()

## Draw connection indicator between snapped buildings
func _draw_connection_indicator(ghost_position: Vector3, snap_point):
	connection_indicator_mesh.clear_surfaces()

	if snap_point == null or not is_instance_valid(snap_point.target):
		return

	var target_pos = snap_point.target.global_position
	var mid_point = (ghost_position + target_pos) / 2.0

	# Draw a thicker line with arrows or connection symbol
	connection_indicator_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Main connection line
	connection_indicator_mesh.surface_add_vertex(ghost_position + Vector3(0, 1.0, 0))
	connection_indicator_mesh.surface_add_vertex(target_pos + Vector3(0, 1.0, 0))

	# Draw small indicator at midpoint
	var indicator_size = 0.5
	connection_indicator_mesh.surface_add_vertex(mid_point + Vector3(-indicator_size, 1.0, 0))
	connection_indicator_mesh.surface_add_vertex(mid_point + Vector3(indicator_size, 1.0, 0))
	connection_indicator_mesh.surface_add_vertex(mid_point + Vector3(0, 1.0, -indicator_size))
	connection_indicator_mesh.surface_add_vertex(mid_point + Vector3(0, 1.0, indicator_size))

	connection_indicator_mesh.surface_end()

## Draw a cube at a specific position
func _draw_cube_at_position(mesh: ImmediateMesh, position: Vector3, size: float, color: Color):
	var half = size / 2.0

	# Define cube vertices
	var vertices = [
		position + Vector3(-half, -half, -half),
		position + Vector3(half, -half, -half),
		position + Vector3(half, -half, half),
		position + Vector3(-half, -half, half),
		position + Vector3(-half, half, -half),
		position + Vector3(half, half, -half),
		position + Vector3(half, half, half),
		position + Vector3(-half, half, half),
	]

	# Draw cube edges
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Bottom face
	mesh.surface_add_vertex(vertices[0])
	mesh.surface_add_vertex(vertices[1])
	mesh.surface_add_vertex(vertices[1])
	mesh.surface_add_vertex(vertices[2])
	mesh.surface_add_vertex(vertices[2])
	mesh.surface_add_vertex(vertices[3])
	mesh.surface_add_vertex(vertices[3])
	mesh.surface_add_vertex(vertices[0])

	# Top face
	mesh.surface_add_vertex(vertices[4])
	mesh.surface_add_vertex(vertices[5])
	mesh.surface_add_vertex(vertices[5])
	mesh.surface_add_vertex(vertices[6])
	mesh.surface_add_vertex(vertices[6])
	mesh.surface_add_vertex(vertices[7])
	mesh.surface_add_vertex(vertices[7])
	mesh.surface_add_vertex(vertices[4])

	# Vertical edges
	mesh.surface_add_vertex(vertices[0])
	mesh.surface_add_vertex(vertices[4])
	mesh.surface_add_vertex(vertices[1])
	mesh.surface_add_vertex(vertices[5])
	mesh.surface_add_vertex(vertices[2])
	mesh.surface_add_vertex(vertices[6])
	mesh.surface_add_vertex(vertices[3])
	mesh.surface_add_vertex(vertices[7])

	mesh.surface_end()

## Clear all visualizations
func clear_all():
	if snap_line_mesh:
		snap_line_mesh.clear_surfaces()
	if snap_points_mesh:
		snap_points_mesh.clear_surfaces()
	if grid_mesh:
		grid_mesh.clear_surfaces()
	if connection_indicator_mesh:
		connection_indicator_mesh.clear_surfaces()

## Toggle snap lines visibility
func set_snap_lines_visible(visible: bool):
	show_snap_lines = visible

## Toggle snap points visibility
func set_snap_points_visible(visible: bool):
	show_snap_points = visible

## Toggle grid visibility
func set_grid_visible(visible: bool):
	show_grid = visible

## Toggle connection indicators visibility
func set_connections_visible(visible: bool):
	show_connections = visible

## Set all visualization on/off
func set_all_visible(visible: bool):
	show_snap_lines = visible
	show_snap_points = visible
	show_grid = visible
	show_connections = visible
	if not visible:
		clear_all()
