extends Node3D

# Terrain settings
@export_group("Terrain Size")
@export var terrain_width: int = 128
@export var terrain_depth: int = 128
@export var terrain_scale: float = 1.0

@export_group("Height Settings")
@export var max_height: float = 3.0
@export var min_height: float = -1.0

@export_group("Noise Settings")
@export var noise_frequency: float = 0.02
@export var noise_octaves: int = 3
@export var noise_lacunarity: float = 2.0
@export var noise_gain: float = 0.4

@export_group("Resource Spawning")
@export var spawn_resources: bool = true
@export var num_gold_nodes: int = 8
@export var num_stone_nodes: int = 12

@export_group("Forest Generation")
@export var num_forests: int = 5
@export var trees_per_forest_min: int = 15
@export var trees_per_forest_max: int = 35
@export var forest_radius: float = 15.0
@export var tree_spacing_min: float = 3.0

@export_group("Generation")
@export var auto_generate: bool = false

@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var terrain_mesh_instance: MeshInstance3D = $NavigationRegion3D/TerrainMesh
@onready var terrain_collision: StaticBody3D = $NavigationRegion3D/TerrainCollision
@onready var collision_shape: CollisionShape3D = $NavigationRegion3D/TerrainCollision/CollisionShape3D

const RESOURCE_NODE_SCENE = preload("res://scripts/resources/resource_node.tscn")

var noise: FastNoiseLite
var heightmap: Array[PackedFloat32Array] = []
var terrain_seed: int = 0

var _vertex_positions: PackedVector3Array = PackedVector3Array()
var _vertex_normals: PackedVector3Array = PackedVector3Array()
var _vertex_uvs: PackedVector2Array = PackedVector2Array()
var _vertex_colors: PackedColorArray = PackedColorArray()
var _mesh_indices: PackedInt32Array = PackedInt32Array()

func _ready():
	auto_generate = false

func generate_terrain(seed_value: int):
	terrain_seed = seed_value
	print("Generating terrain mesh with seed: ", terrain_seed)
	setup_noise(terrain_seed)
	generate_heightmap()
	create_mesh()
	create_collision()
	print("Terrain mesh generation complete!")

func setup_noise(seed_value: int):
	noise = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = noise_frequency
	noise.fractal_octaves = noise_octaves
	noise.fractal_lacunarity = noise_lacunarity
	noise.fractal_gain = noise_gain
	noise.noise_type = FastNoiseLite.TYPE_PERLIN

func generate_heightmap():
	heightmap.clear()
	heightmap.resize(terrain_depth)

	for z in terrain_depth:
		var row: PackedFloat32Array = PackedFloat32Array()
		row.resize(terrain_width)
		for x in terrain_width:
			var noise_value: float = noise.get_noise_2d(x, z)
			var height: float = remap(noise_value, -1.0, 1.0, min_height, max_height)
			row[x] = height
		heightmap[z] = row

func create_mesh():
	_build_vertex_data_from_heightmap()
	_commit_terrain_mesh()

func _build_vertex_data_from_heightmap():
	var vertex_count: int = terrain_width * terrain_depth

	_vertex_positions = PackedVector3Array()
	_vertex_positions.resize(vertex_count)
	_vertex_normals = PackedVector3Array()
	_vertex_normals.resize(vertex_count)
	_vertex_uvs = PackedVector2Array()
	_vertex_uvs.resize(vertex_count)
	_vertex_colors = PackedColorArray()
	_vertex_colors.resize(vertex_count)

	_mesh_indices = PackedInt32Array()
	_mesh_indices.resize((terrain_width - 1) * (terrain_depth - 1) * 6)

	var width_minus_one: int = max(1, terrain_width - 1)
	var depth_minus_one: int = max(1, terrain_depth - 1)
	var index_write: int = 0

	for z in terrain_depth:
		for x in terrain_width:
			var array_index: int = z * terrain_width + x
			var height: float = heightmap[z][x]
			var position: Vector3 = Vector3(x * terrain_scale, height, z * terrain_scale)
			var normal: Vector3 = _calculate_vertex_normal(x, z)
			var slope: float = 1.0 - clamp(normal.y, 0.0, 1.0)
			var color: Color = _calculate_vertex_color(height, slope)

			_vertex_positions[array_index] = position
			_vertex_normals[array_index] = normal
			_vertex_uvs[array_index] = Vector2(float(x) / width_minus_one, float(z) / depth_minus_one)
			_vertex_colors[array_index] = color

	for z in terrain_depth - 1:
		for x in terrain_width - 1:
			var top_left: int = z * terrain_width + x
			var top_right: int = top_left + 1
			var bottom_left: int = top_left + terrain_width
			var bottom_right: int = bottom_left + 1

			_mesh_indices[index_write] = top_left
			_mesh_indices[index_write + 1] = top_right
			_mesh_indices[index_write + 2] = bottom_left
			_mesh_indices[index_write + 3] = top_right
			_mesh_indices[index_write + 4] = bottom_right
			_mesh_indices[index_write + 5] = bottom_left
			index_write += 6

func _commit_terrain_mesh():
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertex_positions
	arrays[Mesh.ARRAY_NORMAL] = _vertex_normals
	arrays[Mesh.ARRAY_TEX_UV] = _vertex_uvs
	arrays[Mesh.ARRAY_COLOR] = _vertex_colors
	arrays[Mesh.ARRAY_INDEX] = _mesh_indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.generate_tangents()

	terrain_mesh_instance.mesh = mesh

func _calculate_vertex_normal(x: int, z: int) -> Vector3:
	var left: float = heightmap[z][max(x - 1, 0)]
	var right: float = heightmap[z][min(x + 1, terrain_width - 1)]
	var forward: float = heightmap[min(z + 1, terrain_depth - 1)][x]
	var back: float = heightmap[max(z - 1, 0)][x]

	var normal := Vector3(left - right, 2.0 * terrain_scale, forward - back)
	return normal.normalized()

func _calculate_vertex_color(height: float, slope: float) -> Color:
	var height_range: float = max(0.001, max_height - min_height)
	var height_normalized: float = clamp((height - min_height) / height_range, 0.0, 1.0)

	var snow: float = smoothstep(0.75, 0.9, height_normalized)
	var rock_height: float = smoothstep(0.55, 0.75, height_normalized)
	var slope_influence: float = smoothstep(0.35, 0.85, slope)
	var rock: float = max(rock_height, slope_influence) * (1.0 - snow)

	var dirt: float = smoothstep(0.3, 0.55, height_normalized) * (1.0 - snow)
	dirt = clamp(dirt, 0.0, 1.0 - snow)

	var grass: float = max(0.0, 1.0 - (rock + snow + dirt))
	var total: float = grass + dirt + rock + snow
	if total <= 0.0:
		grass = 1.0
		total = 1.0

	grass /= total
	dirt /= total
	rock /= total
	snow /= total

	return Color(grass, dirt, rock, snow)

func create_collision():
	if terrain_mesh_instance.mesh == null:
		push_error("Terrain mesh is missing; cannot create collision")
		return

	var faces: PackedVector3Array = terrain_mesh_instance.mesh.get_faces()
	if faces.is_empty():
		push_error("Terrain mesh returned zero faces; collision not created")
		return

	var shape = ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collision_shape.shape = shape
	terrain_collision.collision_layer = 1
	terrain_collision.collision_mask = 1

func _setup_nav_mesh_parameters(nav_mesh: NavigationMesh):
	"""Helper function to set navmesh properties"""
	nav_mesh.cell_size = 0.5
	nav_mesh.cell_height = 0.5
	nav_mesh.agent_height = 2.0
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_max_climb = 2.0
	nav_mesh.agent_max_slope = 45.0
	nav_mesh.region_min_size = 8.0
	nav_mesh.region_merge_size = 20.0
	nav_mesh.edge_max_length = 12.0
	nav_mesh.edge_max_error = 1.3
	nav_mesh.detail_sample_distance = 6.0
	nav_mesh.detail_sample_max_error = 1.0

func _bake_nav_mesh_from_source(nav_mesh: NavigationMesh, source_geometry: NavigationMeshSourceGeometryData3D):
	"""Helper function to perform the bake and enable the region"""
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_geometry)
	
	navigation_region.enabled = false
	await get_tree().process_frame
	navigation_region.enabled = true
	
	await get_tree().physics_frame
	print("  NavMesh baked! Polygons: ", nav_mesh.get_polygon_count())


func bake_base_terrain_navmesh():
	"""
	CRITICAL FIX: This is the FIRST pass bake.
	It bakes *only* the terrain, so units can be spawned.
	"""
	print("  Baking BASE navigation mesh (Terrain Only)...")

	if navigation_region.navigation_mesh == null:
		navigation_region.navigation_mesh = NavigationMesh.new()

	var nav_mesh = navigation_region.navigation_mesh
	_setup_nav_mesh_parameters(nav_mesh)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var source_geometry = NavigationMeshSourceGeometryData3D.new()

	# 1. Add Terrain Geometry ONLY
	if terrain_mesh_instance.mesh == null:
		push_error("Cannot bake navmesh: terrain mesh is missing")
		return

	var mesh_faces = terrain_mesh_instance.mesh.get_faces()
	if mesh_faces.is_empty():
		push_error("Cannot bake navmesh: terrain mesh returned zero faces")
		return

	var mesh_transform = terrain_mesh_instance.global_transform
	source_geometry.add_faces(mesh_faces, mesh_transform)
	print("    Added terrain geometry...")

	# 2. Bake!
	await _bake_nav_mesh_from_source(nav_mesh, source_geometry)

func bake_navigation_with_obstacles():
	"""
	CRITICAL FIX: This is the SECOND pass bake.
	It bakes *after* all obstacles (buildings, resources) are spawned.
	"""
	print("  Baking FINAL navigation mesh (With Obstacles)...")

	if navigation_region.navigation_mesh == null:
		navigation_region.navigation_mesh = NavigationMesh.new()

	var nav_mesh = navigation_region.navigation_mesh
	_setup_nav_mesh_parameters(nav_mesh) # Use the same settings

	await get_tree().physics_frame
	await get_tree().physics_frame

	var source_geometry = NavigationMeshSourceGeometryData3D.new()

	# 1. Add Terrain Geometry
	if terrain_mesh_instance.mesh == null:
		push_error("Cannot bake navmesh: terrain mesh is missing")
		return

	var terrain_mesh_faces = terrain_mesh_instance.mesh.get_faces()
	if terrain_mesh_faces.is_empty():
		push_error("Cannot bake navmesh: terrain mesh returned zero faces")
		return

	var terrain_transform = terrain_mesh_instance.global_transform
	source_geometry.add_faces(terrain_mesh_faces, terrain_transform)
	print("    Added terrain geometry...")

	# 2. Add Building Geometry
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building):
			continue

		# Assumes buildings have a MeshInstance3D child for their model
		var mesh_instance = building.find_child("MeshInstance3D", true, false)
		if mesh_instance and mesh_instance.mesh:
			source_geometry.add_mesh(mesh_instance.mesh, mesh_instance.global_transform)
			print("    Added building: ", building.name)
		else:
			# Fallback: check for StaticBody3D with CollisionShape3D
			var static_body = building.find_child("StaticBody3D", true, false)
			if static_body:
				for child in static_body.get_children():
					if child is CollisionShape3D and child.shape:
						source_geometry.add_collision_shape(child.shape, child.global_transform)
						print("    Added building collision: ", building.name)

	# 3. Add Resource Geometry
	for resource in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(resource):
			continue

		# Assumes resources have a MeshInstance3D for their model
		var mesh_instance = resource.find_child("MeshInstance3D", true, false)
		if mesh_instance and mesh_instance.mesh:
			source_geometry.add_mesh(mesh_instance.mesh, mesh_instance.global_transform)
			print("    Added resource: ", resource.name)
		else:
			# Fallback: check for StaticBody3D with CollisionShape3D
			var static_body = resource.find_child("StaticBody3D", true, false)
			if static_body:
				for child in static_body.get_children():
					if child is CollisionShape3D and child.shape:
						source_geometry.add_collision_shape(child.shape, child.global_transform)
						print("    Added resource collision: ", resource.name)

	# 4. Bake!
	await _bake_nav_mesh_from_source(nav_mesh, source_geometry)
func spawn_resource_nodes():
	"""Spawn all resources - called from game.gd after buildings"""
	if not multiplayer.is_server():
		return
	
	print("\n=== SPAWNING RESOURCES ===")
	
	spawn_forests()
	
	for i in range(num_gold_nodes):
		spawn_resource(0, i)
	
	for i in range(num_stone_nodes):
		spawn_resource(2, i)
	
	print("✓ Resource spawning complete!")

func spawn_forests():
	"""Spawn tree clusters"""
	if not multiplayer.is_server():
		return
	
	var forest_centers = []
	var attempts = 0
	
	while forest_centers.size() < num_forests and attempts < 100:
		attempts += 1
		var center = Vector3(
			randf_range(forest_radius + 10, terrain_width - forest_radius - 10),
			0,
			randf_range(forest_radius + 10, terrain_depth - forest_radius - 10)
		)
		
		var valid = true
		for other in forest_centers:
			if center.distance_to(other) < forest_radius * 2.5:
				valid = false
				break
		
		if valid:
			center.y = get_height_at_position(center)
			forest_centers.append(center)
	
	var tree_id = 0
	for center in forest_centers:
		var tree_count = randi_range(trees_per_forest_min, trees_per_forest_max)
		for i in range(tree_count):
			var angle = randf() * TAU
			var dist = randf_range(tree_spacing_min, forest_radius)
			var pos = center + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
			pos.y = get_height_at_position(pos)
			spawn_tree_rpc.rpc(pos, tree_id)
			tree_id += 1

func spawn_resource(resource_type: int, index: int):
	"""Spawn single resource node"""
	for attempt in range(50):
		var pos = Vector3(
			randf_range(10, terrain_width - 10),
			0,
			randf_range(10, terrain_depth - 10)
		)
		pos.y = get_height_at_position(pos)
		
		# Check distance from town centers
		var valid = true
		for tc in get_tree().get_nodes_in_group("buildings"):
			if pos.distance_to(tc.global_position) < 8.0:
				valid = false
				break
		
		if valid:
			spawn_resource_rpc.rpc(resource_type, pos, index)
			return

@rpc("authority", "call_local", "reliable")
func spawn_tree_rpc(position: Vector3, index: int):
	var tree = RESOURCE_NODE_SCENE.instantiate()
	tree.global_position = position
	tree.resource_type = 1
	tree.name = "Tree_%d" % index
	tree.add_to_group("resources") # Add to group for navmesh baking
	add_child(tree)

@rpc("authority", "call_local", "reliable") 
func spawn_resource_rpc(resource_type: int, position: Vector3, index: int):
	var node = RESOURCE_NODE_SCENE.instantiate()
	node.global_position = position
	node.resource_type = resource_type
	node.name = "Resource_%d_%d" % [resource_type, index]
	node.add_to_group("resources") # Add to group for navmesh baking
	add_child(node)

func get_height_at_position(pos: Vector3) -> float:
	var x = int(clamp(pos.x / terrain_scale, 0, terrain_width - 1))
	var z = int(clamp(pos.z / terrain_scale, 0, terrain_depth - 1))
	if x >= 0 and x < terrain_width and z >= 0 and z < terrain_depth:
		return heightmap[z][x]
	return 0.0
