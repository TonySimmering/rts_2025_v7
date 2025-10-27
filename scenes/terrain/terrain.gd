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
@export var num_forests: int = 5  # Number of forest clusters
@export var trees_per_forest_min: int = 15  # Min trees per forest
@export var trees_per_forest_max: int = 35  # Max trees per forest
@export var forest_radius: float = 15.0  # Size of each forest cluster
@export var tree_spacing_min: float = 3.0  # Min distance between trees

@export_group("Generation")
@export var auto_generate: bool = false

@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var terrain_mesh_instance: MeshInstance3D = $NavigationRegion3D/TerrainMesh
@onready var terrain_collision: StaticBody3D = $NavigationRegion3D/TerrainCollision
@onready var collision_shape: CollisionShape3D = $NavigationRegion3D/TerrainCollision/CollisionShape3D

const RESOURCE_NODE_SCENE = preload("res://scripts/resources/resource_node.tscn")

var noise: FastNoiseLite
var heightmap: Array = []
var terrain_seed: int = 0

func _ready():
	auto_generate = false
	print("Terrain _ready() - auto_generate forcibly set to false")

func generate_terrain(seed_value: int):
	terrain_seed = seed_value
	print("Generating terrain with seed: ", terrain_seed)
	setup_noise(terrain_seed)
	generate_heightmap()
	create_mesh()
	create_collision()
	await bake_navigation()
	
	# Spawn resources after navigation is ready
	if spawn_resources and multiplayer.is_server():
		spawn_resource_nodes()
	
	print("Terrain generation complete!")

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
		heightmap[z] = []
		heightmap[z].resize(terrain_width)
		for x in terrain_width:
			var noise_value = noise.get_noise_2d(x, z)
			var height = remap(noise_value, -1.0, 1.0, min_height, max_height)
			heightmap[z][x] = height

func create_mesh():
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for z in terrain_depth:
		for x in terrain_width:
			var height = heightmap[z][x]
			var vertex_pos = Vector3(
				x * terrain_scale,
				height,
				z * terrain_scale
			)
			
			var uv = Vector2(
				float(x) / float(terrain_width - 1),
				float(z) / float(terrain_depth - 1)
			)
			
			surface_tool.set_uv(uv)
			surface_tool.add_vertex(vertex_pos)
	
	for z in terrain_depth - 1:
		for x in terrain_width - 1:
			var i = z * terrain_width + x
			
			surface_tool.add_index(i)
			surface_tool.add_index(i + 1)
			surface_tool.add_index(i + terrain_width)
			
			surface_tool.add_index(i + 1)
			surface_tool.add_index(i + terrain_width + 1)
			surface_tool.add_index(i + terrain_width)
	
	surface_tool.generate_normals()
	
	var mesh = surface_tool.commit()
	terrain_mesh_instance.mesh = mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.6, 0.2)
	terrain_mesh_instance.set_surface_override_material(0, material)

func create_collision():
	var shape = ConcavePolygonShape3D.new()
	var faces = terrain_mesh_instance.mesh.get_faces()
	shape.set_faces(faces)
	collision_shape.shape = shape
	
	terrain_collision.collision_layer = 1
	terrain_collision.collision_mask = 1
	
	print("  Collision created with ", faces.size() / 3, " triangles")

func bake_navigation():
	print("  Baking navigation mesh...")
	
	if navigation_region.navigation_mesh == null:
		navigation_region.navigation_mesh = NavigationMesh.new()
	
	var nav_mesh = navigation_region.navigation_mesh
	
	nav_mesh.cell_size = 1.0
	nav_mesh.cell_height = 0.2
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_radius = 0.3
	nav_mesh.agent_max_climb = 3.0
	nav_mesh.agent_max_slope = 60.0
	nav_mesh.region_min_size = 0.5
	nav_mesh.detail_sample_distance = 6.0
	nav_mesh.detail_sample_max_error = 1.0
	
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var source_geometry = NavigationMeshSourceGeometryData3D.new()
	var mesh_faces = terrain_mesh_instance.mesh.get_faces()
	var mesh_transform = terrain_mesh_instance.global_transform
	source_geometry.add_faces(mesh_faces, mesh_transform)
	
	print("  Added ", mesh_faces.size() / 3, " triangles to source geometry")
	
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_geometry)
	
	var poly_count = nav_mesh.get_polygon_count()
	print("  NavMesh baked! Polygons: ", poly_count)
	
	if poly_count < 500:
		push_warning("  ⚠ Low NavMesh coverage! Only ", poly_count, " polygons")
	
	navigation_region.enabled = false
	await get_tree().process_frame
	navigation_region.enabled = true
	
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var world_nav_map = get_world_3d().navigation_map
	print("  World navigation map RID: ", world_nav_map)
	print("  NavigationRegion map RID: ", navigation_region.get_navigation_map())

func spawn_resource_nodes():
	"""Spawn resource nodes across the terrain (server only)"""
	if not multiplayer.is_server():
		print("⚠ Not server, skipping resource spawn")
		return
	
	print("\n=== SPAWNING RESOURCES ===")
	print("Is Server: ", multiplayer.is_server())
	
	# Spawn forests (clusters of trees)
	spawn_forests()
	
	# Spawn individual resource nodes
	print("\nSpawning gold nodes: ", num_gold_nodes)
	for i in range(num_gold_nodes):
		spawn_resource(0, i)  # Type 0 = Gold
	
	print("Spawning stone nodes: ", num_stone_nodes)
	for i in range(num_stone_nodes):
		spawn_resource(2, i)  # Type 2 = Stone
	
	await get_tree().create_timer(0.5).timeout  # Give time for spawning
	
	print("✓ Resource spawning complete!")
	print("Total resources in scene: ", get_tree().get_nodes_in_group("resource_nodes").size())
	print("=========================\n")

func spawn_forests():
	"""Generate realistic forest clusters"""
	print("\n--- FOREST GENERATION ---")
	print("Generating ", num_forests, " forest clusters...")
	
	var nav_map = get_world_3d().navigation_map
	var forest_centers: Array[Vector3] = []
	
	# Generate forest center points (well-spaced)
	var min_forest_spacing = forest_radius * 2.5
	
	for forest_idx in range(num_forests):
		var attempts = 0
		var max_attempts = 100
		var forest_center: Vector3
		var placed = false
		
		while attempts < max_attempts:
			# Random position with margins
			forest_center = Vector3(
				randf_range(forest_radius + 10, terrain_width - forest_radius - 10),
				0,
				randf_range(forest_radius + 10, terrain_depth - forest_radius - 10)
			)
			
			# Check distance from other forest centers
			var too_close = false
			for existing_center in forest_centers:
				if forest_center.distance_to(existing_center) < min_forest_spacing:
					too_close = true
					break
			
			if not too_close:
				forest_centers.append(forest_center)
				print("  ✓ Forest ", forest_idx + 1, " center placed at: ", forest_center)
				placed = true
				break
			
			attempts += 1
		
		if not placed:
			print("  ⚠ Could not place forest ", forest_idx + 1, " after ", max_attempts, " attempts")
	
	print("\nTotal forest centers placed: ", forest_centers.size())
	
	# Spawn trees in each forest
	var total_trees_spawned = 0
	
	for forest_idx in range(forest_centers.size()):
		var center = forest_centers[forest_idx]
		var num_trees = randi_range(trees_per_forest_min, trees_per_forest_max)
		
		print("\n  Spawning forest ", forest_idx + 1, " with target of ", num_trees, " trees...")
		
		var trees_in_forest: Array[Vector3] = []
		
		for tree_idx in range(num_trees):
			var placed = false
			var attempts = 0
			var max_tree_attempts = 50
			
			while not placed and attempts < max_tree_attempts:
				# Use exponential distribution for more density near center
				var distance = randf() * randf() * forest_radius
				var angle = randf() * TAU
				
				var tree_pos = center + Vector3(
					cos(angle) * distance,
					0,
					sin(angle) * distance
				)
				
				# Bounds check
				if tree_pos.x < 5 or tree_pos.x > terrain_width - 5 or tree_pos.z < 5 or tree_pos.z > terrain_depth - 5:
					attempts += 1
					continue
				
				# Validate with NavMesh (more lenient)
				var valid_pos = NavigationServer3D.map_get_closest_point(nav_map, tree_pos)
				
				# Much more lenient - just needs to be somewhere reasonable
				if valid_pos.distance_to(tree_pos) > 20.0:
					attempts += 1
					continue
				
				# Check spacing from other trees in this forest only
				var too_close = false
				for existing_tree in trees_in_forest:
					if valid_pos.distance_to(existing_tree) < tree_spacing_min:
						too_close = true
						break
				
				if not too_close:
					trees_in_forest.append(valid_pos)
					# Spawn immediately with unique index
					var global_tree_index = total_trees_spawned
					spawn_tree_at_position(valid_pos, global_tree_index)
					total_trees_spawned += 1
					placed = true
				
				attempts += 1
			
			if not placed and attempts >= max_tree_attempts:
				if tree_idx % 5 == 0:  # Only print every 5th failure to reduce spam
					print("    ⚠ Could not place tree ", tree_idx, " in forest ", forest_idx + 1)
		
		print("    ✓ Placed ", trees_in_forest.size(), " / ", num_trees, " trees in forest ", forest_idx + 1)
	
	print("\n  Total trees spawned: ", total_trees_spawned)
	print("--- FOREST GENERATION COMPLETE ---")

func spawn_tree_at_position(position: Vector3, index: int):
	"""Directly spawn a tree (wood resource) at position"""
	spawn_resource_rpc.rpc(1, position, index)  # Type 1 = Wood

func spawn_resource(resource_type: int, index: int):
	"""Spawn a single resource node (gold/stone)"""
	var max_attempts = 50
	var nav_map = get_world_3d().navigation_map
	
	for attempt in range(max_attempts):
		# Random position on terrain
		var random_x = randf_range(10, terrain_width - 10)
		var random_z = randf_range(10, terrain_depth - 10)
		var test_pos = Vector3(random_x, 0, random_z)
		
		# Get valid NavMesh position
		var valid_pos = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
		
		var distance_to_navmesh = valid_pos.distance_to(test_pos)
		
		if distance_to_navmesh > 15.0:
			continue
		
		# Check minimum distance from other resources
		var too_close = false
		for existing in get_tree().get_nodes_in_group("resource_nodes"):
			if existing.global_position.distance_to(valid_pos) < 5.0:
				too_close = true
				break
		
		if too_close:
			continue
		
		# Success! Spawn the resource
		spawn_resource_rpc.rpc(resource_type, valid_pos, index)
		return
	
	# Fallback: spawn without NavMesh validation
	var fallback_pos = Vector3(
		randf_range(20, terrain_width - 20),
		0,
		randf_range(20, terrain_depth - 20)
	)
	spawn_resource_rpc.rpc(resource_type, fallback_pos, index)

@rpc("authority", "call_local", "reliable")
func spawn_resource_rpc(resource_type: int, position: Vector3, index: int):
	"""Spawn resource on all clients"""
	var type_names = ["Gold", "Wood", "Stone"]
	
	var resource_node = RESOURCE_NODE_SCENE.instantiate()
	
	resource_node.resource_type = resource_type
	resource_node.global_position = position
	resource_node.name = "Resource_%d_%d" % [resource_type, index]
	
	navigation_region.add_child(resource_node)
	
	# Debug output (only print every 10th tree to reduce spam)
	if resource_type == 1 and index % 10 == 0:
		print("    Tree batch spawned: ", index, " at ", position)

func get_height_at_position(world_pos: Vector3) -> float:
	var local_x = int(world_pos.x / terrain_scale)
	var local_z = int(world_pos.z / terrain_scale)
	
	local_x = clamp(local_x, 0, terrain_width - 1)
	local_z = clamp(local_z, 0, terrain_depth - 1)
	
	if local_z < heightmap.size() and local_x < heightmap[local_z].size():
		return heightmap[local_z][local_x]
	return 0.0
