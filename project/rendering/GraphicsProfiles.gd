extends Node
## GraphicsProfiles — Perfiles de calidad automáticos y escalado dinámico (autoload).
##
## Detecta la GPU y recomienda un perfil (Bajo/Medio/Alto/Ultra). Aplica los ajustes
## al Environment y al Viewport (SDFGI, SSAO/SSIL, SSR, glow, niebla, AA, escala 3D).
## Incluye escalado dinámico de resolución para mantener FPS estables.

enum Profile { BAJO, MEDIO, ALTO, ULTRA }

const PROFILE_NAMES := {
	Profile.BAJO: "Bajo", Profile.MEDIO: "Medio", Profile.ALTO: "Alto", Profile.ULTRA: "Ultra",
}

# Definición declarativa de cada perfil.
const SETTINGS := {
	Profile.BAJO: {
		"scale3d": 0.7, "msaa": Viewport.MSAA_DISABLED, "taa": false,
		"ssao": false, "ssil": false, "ssr": false, "sdfgi": false,
		"glow": false, "fog": false, "shadow_size": 2048,
	},
	Profile.MEDIO: {
		"scale3d": 0.85, "msaa": Viewport.MSAA_2X, "taa": true,
		"ssao": true, "ssil": false, "ssr": false, "sdfgi": false,
		"glow": true, "fog": false, "shadow_size": 3072,
	},
	Profile.ALTO: {
		"scale3d": 1.0, "msaa": Viewport.MSAA_4X, "taa": true,
		"ssao": true, "ssil": true, "ssr": true, "sdfgi": true,
		"glow": true, "fog": true, "shadow_size": 4096,
	},
	Profile.ULTRA: {
		"scale3d": 1.0, "msaa": Viewport.MSAA_8X, "taa": true,
		"ssao": true, "ssil": true, "ssr": true, "sdfgi": true,
		"glow": true, "fog": true, "shadow_size": 8192,
	},
}

var current_profile: int = Profile.ALTO

## Antialiasing elegido por el usuario (-1 = el del perfil: TAA + MSAA).
enum AA { PERFIL, TAA_MSAA, SMAA, FXAA, NINGUNO }
const AA_NAMES := ["Automático (perfil)", "TAA + MSAA", "SMAA", "FXAA", "Sin AA"]
var aa_mode: int = AA.PERFIL
var adapter_name: String = ""
var adapter_vendor: String = ""

# --- Escalado dinámico de resolución ---
var dynamic_scaling_enabled: bool = true
var target_fps: float = 60.0
var _min_scale := 0.6
var _max_scale := 1.0
var _current_scale := 1.0
var _accum := 0.0
var _env: Environment
var _viewport: Viewport

func _ready() -> void:
	adapter_name = RenderingServer.get_video_adapter_name()
	adapter_vendor = RenderingServer.get_video_adapter_vendor()

## Recomienda un perfil según la GPU detectada (heurística por nombre de adaptador).
func recommend_profile() -> int:
	var n := adapter_name.to_lower()
	# Gama alta dedicada.
	if n.contains("rtx") or n.contains("radeon rx") or n.contains("arc a"):
		# Serie xx60 o superior => Ultra; heurística simple.
		return Profile.ULTRA
	if n.contains("gtx") or n.contains("quadro"):
		return Profile.ALTO
	# GPU integrada / desconocida.
	if n.contains("intel") or n.contains("vega") or n.contains("radeon(tm) graphics"):
		return Profile.MEDIO
	return Profile.ALTO

func profile_name(p: int = -1) -> String:
	if p < 0:
		p = current_profile
	return PROFILE_NAMES.get(p, "Alto")

## Aplica un perfil al Environment y Viewport dados.
func apply_profile(p: int, env: Environment, viewport: Viewport) -> void:
	current_profile = p
	_env = env
	_viewport = viewport
	var s: Dictionary = SETTINGS[p]

	# Viewport: escala 3D y antialiasing.
	_current_scale = s["scale3d"]
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if s["taa"] else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = _current_scale
	viewport.msaa_3d = s["msaa"]
	viewport.screen_space_aa = (Viewport.SCREEN_SPACE_AA_DISABLED)
	viewport.use_taa = s["taa"]
	_apply_aa()

	RenderingServer.directional_shadow_atlas_set_size(int(s["shadow_size"]), true)

	# Environment: GI, oclusión, reflejos, glow, niebla.
	if env:
		env.ssao_enabled = s["ssao"]
		env.ssil_enabled = s["ssil"]
		env.ssr_enabled = s["ssr"]
		env.sdfgi_enabled = s["sdfgi"]
		env.glow_enabled = s["glow"]
		env.volumetric_fog_enabled = s["fog"]

	Config.quality_profile_changed.emit(profile_name(p))
	Config.notify("Perfil gráfico: %s (GPU: %s)" % [profile_name(p), adapter_name], 4.0)

## Cambia el modo de antialiasing (post-procesado SMAA/FXAA o temporal TAA).
func set_aa_mode(m: int) -> void:
	aa_mode = m
	_apply_aa()

func _apply_aa() -> void:
	if _viewport == null:
		return
	var s: Dictionary = SETTINGS[current_profile]
	match aa_mode:
		AA.TAA_MSAA:
			_viewport.use_taa = true
			_viewport.msaa_3d = Viewport.MSAA_4X
			_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		AA.SMAA:
			_viewport.use_taa = false
			_viewport.msaa_3d = Viewport.MSAA_DISABLED
			_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		AA.FXAA:
			_viewport.use_taa = false
			_viewport.msaa_3d = Viewport.MSAA_DISABLED
			_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		AA.NINGUNO:
			_viewport.use_taa = false
			_viewport.msaa_3d = Viewport.MSAA_DISABLED
			_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		_:
			_viewport.use_taa = s["taa"]
			_viewport.msaa_3d = s["msaa"]
			_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	# FSR2 necesita datos temporales; sin TAA se usa escalado bilineal.
	_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if _viewport.use_taa else Viewport.SCALING_3D_MODE_BILINEAR

## Aplica automáticamente el perfil recomendado.
func apply_auto(env: Environment, viewport: Viewport) -> int:
	var p := recommend_profile()
	apply_profile(p, env, viewport)
	return p

## Escalado dinámico: llamar cada frame con el delta para ajustar la resolución.
func update_dynamic(delta: float) -> void:
	if not dynamic_scaling_enabled or _viewport == null:
		return
	_accum += delta
	if _accum < 0.5:
		return
	_accum = 0.0
	var fps := Engine.get_frames_per_second()
	if fps < target_fps - 5.0:
		_current_scale = maxf(_min_scale, _current_scale - 0.05)
		_viewport.scaling_3d_scale = _current_scale
	elif fps > target_fps + 12.0 and _current_scale < _max_scale:
		_current_scale = minf(_max_scale, _current_scale + 0.02)
		_viewport.scaling_3d_scale = _current_scale

func current_scale() -> float:
	return _current_scale

func hardware_summary() -> String:
	return "%s / %s" % [adapter_vendor, adapter_name]
