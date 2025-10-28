extends WorldEnvironment

func _ready():
	# Create environment
	environment = Environment.new()
	
	# === SKY SETUP ===
	var sky = Sky.new()
	var sky_material = ProceduralSkyMaterial.new()
	
	# Sky colors for stylized look
	sky_material.sky_top_color = Color(0.4, 0.6, 1.0)  # Bright blue
	sky_material.sky_horizon_color = Color(0.7, 0.85, 1.0)  # Light blue
	sky_material.ground_bottom_color = Color(0.2, 0.3, 0.4)  # Dark blue-gray
	sky_material.ground_horizon_color = Color(0.5, 0.6, 0.7)  # Medium gray
	sky_material.sun_angle_max = 30.0
	sky_material.sun_curve = 0.15
	
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	
	# === AMBIENT LIGHT ===
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color(0.8, 0.85, 1.0)
	environment.ambient_light_sky_contribution = 0.5
	environment.ambient_light_energy = 0.8
	
	# === TONEMAP (for stylized look) ===
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.1
	environment.tonemap_white = 1.2
	
	# === SSAO (Subtle) ===
	environment.ssao_enabled = true
	environment.ssao_radius = 2.0
	environment.ssao_intensity = 1.5
	environment.ssao_detail = 0.5
	
	# === GLOW (Optional, for magical feel) ===
	environment.glow_enabled = false  # Enable if you want bloom
	environment.glow_intensity = 0.3
	environment.glow_strength = 0.8
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	
	# === FOG (Optional depth) ===
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.7, 0.8, 1.0)
	environment.fog_light_energy = 1.0
	environment.fog_density = 0.0005
	environment.fog_sky_affect = 0.5
	
	print("Stylized lighting environment configured")
