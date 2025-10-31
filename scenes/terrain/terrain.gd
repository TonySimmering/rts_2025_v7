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

@export_group("Texture Settings")
@export var use_procedural_textures: bool = true
@export var use_texture_files: bool = false  # Toggle for custom textures
@export var grass_texture_path: String = ""
@export var dirt_texture_path: String = ""
@export var rock_texture_path: String = ""
@export var snow_texture_path: String = ""
@export var grass_normal_path: String = ""
@export var dirt_normal_path: String = ""
@export var rock_normal_path: String = ""
@export var snow_normal_path: String = ""
@export var grass_color: Color = Color(0.3, 0.6, 0.2)
@export var dirt_color: Color = Color(0.45, 0.35, 0.25)
@export var rock_color: Color = Color(0.5, 0.5, 0.5)
@export var snow_color: Color = Color(0.9, 0.9, 0.95)
@export_range(0.0, 5.0) var height_blend_sharpness: float = 2.0
@export_range(0.0, 1.0) var slope_influence: float = 0.5
@export var texture_scale: float = 10.0  # UV tiling
@export var use_triplanar_mapping: bool = true  # Better for steep slopes
@export_range(0.0, 1.0) var terrain_roughness: float = 1.0
@export_range(0.0, 2.0) var normal_map_strength: float = 1.0

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
var heightmap: Array = []
var terrain_seed: int = 0
var vertex_colors: PackedColorArray = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Track all flattened areas for persistent dirt texture
# Each entry: {position: Vector3, radius: float, blend_padding: float}
var flattened_areas: Array = []

func _ready():
	auto_generate = false
	print("Terrain _ready() - auto_generate forcibly set to false")

func generate_terrain(seed_value: int):
	terrain_seed = seed_value
	print("Generating terrain with seed: ", terrain_seed)
	rng.seed = terrain_seed
	setup_noise(terrain_seed)
	generate_heightmap()
	create_mesh()
	create_collision()
	await bake_navigation()
	
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
	
	vertex_colors.clear()
	
	# Build vertices
	for z in terrain_depth:
		for x in terrain_width:
			var height = heightmap[z][x]
			var vertex_pos = Vector3(
				x * terrain_scale,
				height,
				z * terrain_scale
			)
			
			# Calculate UV coordinates
			var uv = Vector2(
				float(x) / float(terrain_width - 1) * texture_scale,
				float(z) / float(terrain_depth - 1) * texture_scale
			)
			
			# Calculate vertex color based on slope angle
			var color = calculate_terrain_color(x, z, height)
			
			surface_tool.set_uv(uv)
			surface_tool.set_color(color)
			surface_tool.add_vertex(vertex_pos)
	
	# Build triangles
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
	
	# Apply material with vertex colors
	apply_terrain_material()

func calculate_terrain_color(x: int, z: int, height: float) -> Color:
	"""Calculate blend weights for textures based ONLY on slope angle, stored in RGBA channels"""
	
	# Calculate slope (steepness) in degrees
	var slope = calculate_slope(x, z)
	
	# Initialize blend weights (R=grass, G=dirt, B=rock, A=unused)
	var grass_weight = 0.0
	var dirt_weight = 0.0  # Reserved for player-flattened terrain
	var rock_weight = 0.0
	var snow_weight = 0.0  # Unused
	
	# Blend based ONLY on slope angle:
	# 0-15 degrees: pure grass (flat terrain)
	# 15-35 degrees: blend grass to rock
	# 35+ degrees: pure rock (steep cliffs)
	
	if slope < 15.0:
		# Flat terrain - pure grass
		grass_weight = 1.0
	elif slope < 35.0:
		# Moderate slopes - blend from grass to rock
		var blend = inverse_lerp(15.0, 35.0, slope)
		blend = pow(blend, height_blend_sharpness)  # Use existing sharpness parameter
		grass_weight = 1.0 - blend
		rock_weight = blend
	else:
		# Steep slopes - pure rock
		rock_weight = 1.0
	
	# Normalize weights to sum to 1.0
	var total = grass_weight + dirt_weight + rock_weight + snow_weight
	if total > 0.0:
		grass_weight /= total
		dirt_weight /= total
		rock_weight /= total
		snow_weight /= total
	
	# If using procedural colors, blend them for preview
	if not use_texture_files:
		var final_color = grass_color * grass_weight + dirt_color * dirt_weight + rock_color * rock_weight + snow_color * snow_weight
		return final_color
	else:
		# Return blend weights in RGBA for shader
		return Color(grass_weight, dirt_weight, rock_weight, snow_weight)

func calculate_slope(x: int, z: int) -> float:
	"""Calculate slope angle in degrees at given position"""
	if x <= 0 or x >= terrain_width - 1 or z <= 0 or z >= terrain_depth - 1:
		return 0.0
	
	var height_center = heightmap[z][x]
	var height_right = heightmap[z][x + 1]
	var height_up = heightmap[z + 1][x]
	
	# Calculate gradients
	var dx = (height_right - height_center) / terrain_scale
	var dz = (height_up - height_center) / terrain_scale
	
	# Calculate slope angle
	var slope_radians = atan(sqrt(dx * dx + dz * dz))
	return rad_to_deg(slope_radians)

func flatten_terrain_at_position(world_pos: Vector3, radius: float = 10.0, blend_padding: float = 3.0):
	"""
	Flatten terrain and set to dirt texture at the given world position with smooth blending.

	IMPORTANT: This modification is PERMANENT for the runtime. The heightmap and vertex colors
	are modified directly and will persist even if the building is destroyed. This allows
	multiple buildings to be constructed on the same flattened terrain without re-flattening.

	If a new building is placed in the same location, this function will be called again,
	overwriting the previous terrain modification.
	"""
	print("🔨 Flattening terrain at ", world_pos, " with radius ", radius, " (PERMANENT modification)")

	# Add this flattened area to the tracking list
	flattened_areas.append({
		"position": world_pos,
		"radius": radius,
		"blend_padding": blend_padding
	})
	print("   Total flattened areas: ", flattened_areas.size())

	# Convert world position to grid coordinates
	var grid_x = int(world_pos.x / terrain_scale)
	var grid_z = int(world_pos.z / terrain_scale)
	
	# Sample the target height at the center
	if grid_x < 0 or grid_x >= terrain_width or grid_z < 0 or grid_z >= terrain_depth:
		push_warning("Flatten position out of terrain bounds")
		return
	
	var target_height = heightmap[grid_z][grid_x]
	
	# Calculate affected area with blend padding
	var total_radius = radius + blend_padding
	var grid_radius = int(total_radius / terrain_scale) + 1
	
	# Flatten the heightmap
	for z in range(terrain_depth):
		for x in range(terrain_width):
			var world_vertex = Vector3(x * terrain_scale, 0, z * terrain_scale)
			var distance = Vector2(world_vertex.x, world_vertex.z).distance_to(Vector2(world_pos.x, world_pos.z))
			
			if distance < radius:
				# Fully flatten
				heightmap[z][x] = target_height
			elif distance < total_radius:
				# Blend zone
				var blend_factor = (distance - radius) / blend_padding
				blend_factor = smoothstep(0.0, 1.0, blend_factor)  # Smooth interpolation
				heightmap[z][x] = lerp(target_height, heightmap[z][x], blend_factor)
	
	# Rebuild mesh with new heights and textures
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Rebuild vertices
	for z in terrain_depth:
		for x in terrain_width:
			var height = heightmap[z][x]
			var vertex_pos = Vector3(
				x * terrain_scale,
				height,
				z * terrain_scale
			)
			
			var uv = Vector2(
				float(x) / float(terrain_width - 1) * texture_scale,
				float(z) / float(terrain_depth - 1) * texture_scale
			)
			
			# Check against ALL flattened areas to determine texture
			var world_vertex = Vector3(x * terrain_scale, 0, z * terrain_scale)
			var color: Color
			var is_dirt = false
			var closest_blend_factor = 1.0  # 1.0 = normal terrain, 0.0 = pure dirt

			# Check all flattened areas
			for area in flattened_areas:
				var area_pos = area.position
				var area_radius = area.radius
				var area_blend = area.blend_padding
				var area_total_radius = area_radius + area_blend

				var distance = Vector2(world_vertex.x, world_vertex.z).distance_to(Vector2(area_pos.x, area_pos.z))

				if distance < area_radius:
					# Inside a flattened area - pure dirt
					is_dirt = true
					closest_blend_factor = 0.0
					break  # No need to check further
				elif distance < area_total_radius:
					# In blend zone - calculate blend factor
					var blend_factor = (distance - area_radius) / area_blend
					blend_factor = smoothstep(0.0, 1.0, blend_factor)

					# Use the strongest dirt influence (lowest blend factor)
					if blend_factor < closest_blend_factor:
						closest_blend_factor = blend_factor
						is_dirt = true

			# Apply the calculated color
			if is_dirt:
				var normal_color = calculate_terrain_color(x, z, height)
				var dirt_color_pure = Color(0.0, 1.0, 0.0, 0.0)
				color = lerp(dirt_color_pure, normal_color, closest_blend_factor)
			else:
				# Normal terrain texture
				color = calculate_terrain_color(x, z, height)
			
			surface_tool.set_uv(uv)
			surface_tool.set_color(color)
			surface_tool.add_vertex(vertex_pos)
	
	# Rebuild triangles
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
	
	# Reapply material
	apply_terrain_material()
	
	# Recreate collision
	create_collision()
	
	# Rebake navigation
	await bake_navigation()

	print("✅ Terrain flattened and rebaked successfully! (Modifications are PERMANENT for this runtime session)")

func get_height_at_position(world_pos: Vector3) -> float:
	"""Get terrain height at a world position"""
	var grid_x = int(world_pos.x / terrain_scale)
	var grid_z = int(world_pos.z / terrain_scale)
	
	# Clamp to valid range
	grid_x = clampi(grid_x, 0, terrain_width - 1)
	grid_z = clampi(grid_z, 0, terrain_depth - 1)
	
	return heightmap[grid_z][grid_x]

func apply_terrain_material():
	if use_texture_files:
		# Use shader-based material with custom textures
		var shader_material = ShaderMaterial.new()
		
		# Load shader
		var shader = load("res://scenes/terrain/terrain_shader.gdshader")
		if not shader:
			push_error("Failed to load terrain_shader.gdshader! Using fallback material.")
			apply_fallback_material()
			return
		
		shader_material.shader = shader
		
		# Load and set textures
		var grass_tex = load_texture(grass_texture_path)
		var dirt_tex = load_texture(dirt_texture_path)
		var rock_tex = load_texture(rock_texture_path)
		var snow_tex = load_texture(snow_texture_path)
		
		if grass_tex:
			shader_material.set_shader_parameter("grass_texture", grass_tex)
		if dirt_tex:
			shader_material.set_shader_parameter("dirt_texture", dirt_tex)
		if rock_tex:
			shader_material.set_shader_parameter("rock_texture", rock_tex)
		if snow_tex:
			shader_material.set_shader_parameter("snow_texture", snow_tex)
		
		# Load and set normal maps (optional)
		if grass_normal_path != "":
			var grass_norm = load_texture(grass_normal_path)
			if grass_norm:
				shader_material.set_shader_parameter("grass_normal", grass_norm)
		
		if dirt_normal_path != "":
			var dirt_norm = load_texture(dirt_normal_path)
			if dirt_norm:
				shader_material.set_shader_parameter("dirt_normal", dirt_norm)
		
		if rock_normal_path != "":
			var rock_norm = load_texture(rock_normal_path)
			if rock_norm:
				shader_material.set_shader_parameter("rock_normal", rock_norm)
		
		if snow_normal_path != "":
			var snow_norm = load_texture(snow_normal_path)
			if snow_norm:
				shader_material.set_shader_parameter("snow_normal", snow_norm)
		
		# Set shader parameters
		shader_material.set_shader_parameter("texture_scale", texture_scale)
		shader_material.set_shader_parameter("roughness", terrain_roughness)
		shader_material.set_shader_parameter("normal_strength", normal_map_strength)
		shader_material.set_shader_parameter("use_triplanar", use_triplanar_mapping)
		shader_material.set_shader_parameter("use_vertex_blend", true)
		
		terrain_mesh_instance.set_surface_override_material(0, shader_material)
		print("  Applied shader-based material with custom textures")
	else:
		# Use simple vertex color material
		apply_fallback_material()

func apply_fallback_material():
	"""Apply simple StandardMaterial3D with vertex colors"""
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = terrain_roughness
	material.metallic = 0.0
	material.ao_enabled = true
	material.ao_light_affect = 0.5
	terrain_mesh_instance.set_surface_override_material(0, material)
	print("  Applied vertex color material")

func load_texture(path: String) -> Texture2D:
	"""Load a texture from file path"""
	if path == "" or path == null:
		return null
	
	if ResourceLoader.exists(path):
		var texture = load(path)
		if texture is Texture2D:
			return texture
		else:
			push_warning("File at ", path, " is not a valid texture")
			return null
	else:
		push_warning("Texture file not found: ", path)
		return null

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
	
	spawn_forests()
	
	print("\nSpawning gold nodes: ", num_gold_nodes)
	for i in range(num_gold_nodes):
		spawn_resource(0, i)
	
	print("Spawning stone nodes: ", num_stone_nodes)
	for i in range(num_stone_nodes):
		spawn_resource(2, i)
	
	await get_tree().create_timer(0.5).timeout
	
	print("✓ Resource spawning complete!")
	print("Total resources in scene: ", get_tree().get_nodes_in_group("resource_nodes").size())
	print("=========================\n")

func spawn_forests():
	"""Generate realistic forest clusters"""
	print("\n--- FOREST GENERATION ---")
	print("Generating ", num_forests, " forest clusters...")
	
	var forest_centers: Array[Vector3] = []
	var min_forest_spacing = forest_radius * 2.5
	
	for forest_idx in range(num_forests):
		var attempts = 0
		var max_attempts = 100
		var forest_center: Vector3
		var placed = false
		
		while attempts < max_attempts:
			var center_x = rng.randf_range(forest_radius + 10, terrain_width - forest_radius - 10)
			var center_z = rng.randf_range(forest_radius + 10, terrain_depth - forest_radius - 10)
			
			forest_center = Vector3(center_x, 0, center_z)
			
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
	
	var total_trees_spawned = 0
	
	for forest_idx in range(forest_centers.size()):
		var center = forest_centers[forest_idx]
		var num_trees = rng.randi_range(trees_per_forest_min, trees_per_forest_max)
		
		print("\n  Spawning forest ", forest_idx + 1, " with target of ", num_trees, " trees...")
		
		var trees_in_forest: Array[Vector3] = []
		
		for tree_idx in range(num_trees):
			var placed = false
			var attempts = 0
			var max_tree_attempts = 50
			
			while not placed and attempts < max_tree_attempts:
				var distance = rng.randf() * rng.randf() * forest_radius
				var angle = rng.randf() * TAU
				
				var tree_x = center.x + cos(angle) * distance
				var tree_z = center.z + sin(angle) * distance
				
				if tree_x < 5 or tree_x > terrain_width - 5 or tree_z < 5 or tree_z > terrain_depth - 5:
					attempts += 1
					continue
				
				var tree_y = get_height_at_position(Vector3(tree_x, 0, tree_z))
				var tree_pos = Vector3(tree_x, tree_y, tree_z)
				
				var too_close = false
				for existing_tree in trees_in_forest:
					if tree_pos.distance_to(existing_tree) < tree_spacing_min:
						too_close = true
						break
				
				if not too_close:
					trees_in_forest.append(tree_pos)
					var global_tree_index = total_trees_spawned
					spawn_tree_at_position(tree_pos, global_tree_index)
					total_trees_spawned += 1
					placed = true
				
				attempts += 1
		
		print("    ✓ Placed ", trees_in_forest.size(), " / ", num_trees, " trees in forest ", forest_idx + 1)
	
	print("\n  Total trees spawned: ", total_trees_spawned)
	print("--- FOREST GENERATION COMPLETE ---")

func spawn_tree_at_position(position: Vector3, index: int):
	# Trees use their index as seed
	var tree_seed = terrain_seed + index * 1000 + 500  # Offset to differentiate from rocks
	spawn_resource_rpc.rpc(1, position, index, tree_seed)

func spawn_resource(resource_type: int, index: int):
	"""Spawn a single resource node (gold/stone) with unique seed"""
	var max_attempts = 50

	# Generate unique seed for this resource based on terrain seed, type, and index
	var resource_seed = terrain_seed + resource_type * 10000 + index * 100

	for attempt in range(max_attempts):
		var random_x = rng.randf_range(10, terrain_width - 10)
		var random_z = rng.randf_range(10, terrain_depth - 10)

		var world_pos = Vector3(random_x, 0, random_z)
		var height = get_height_at_position(world_pos)
		world_pos.y = height

		spawn_resource_rpc.rpc(resource_type, world_pos, index, resource_seed)
		return

	push_warning("Failed to spawn resource after ", max_attempts, " attempts")

@rpc("authority", "call_local", "reliable")
func spawn_resource_rpc(resource_type: int, position: Vector3, index: int, seed_value: int):
	"""Spawn a resource node on all clients with procedural generation seed"""
	var resource_node = RESOURCE_NODE_SCENE.instantiate()
	resource_node.global_position = position
	resource_node.resource_type = resource_type
	resource_node.resource_seed = seed_value  # Pass seed for procedural generation
	resource_node.name = "Resource_%d_%d" % [resource_type, index]
	add_child(resource_node)
