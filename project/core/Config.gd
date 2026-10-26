extends Node
## Config — Configuración global y bus de señales de MechaForge (autoload).
##
## Centraliza los ajustes de la aplicación (unidades, rejilla, snapping) y actúa
## como bus de señales desacoplado entre módulos (core, ui, rendering).
## Todas las magnitudes se manejan en unidades SI (metros, kg, N, etc.).

# --- Señales globales (bus de eventos) ---
signal grid_settings_changed
signal quality_profile_changed(profile_name: String)
signal status_message(text: String, seconds: float)

# --- Rejilla y snapping ---
## Tamaño de celda de la rejilla en metros (por defecto 10 mm = 0.01 m).
var grid_size_m: float = 0.01
var snap_enabled: bool = true
## Encaje por superficie: al arrastrar/colocar una pieza sobre otra, se posa
## automáticamente sobre la cara que toca (apilado sin ajustar en 3 ejes).
var surface_snap_enabled: bool = true
## Paso de rotación en grados al rotar piezas.
var rotation_step_deg: float = 15.0

# --- Batería del sistema (Fase 3) ---
var battery_voltage: float = 12.0        # V
var battery_capacity_mah: float = 2200.0 # mAh

# --- Estado de proyecto ---
var current_project_path: String = ""
var project_dirty: bool = false

const APP_NAME := "MechaForge"
## La de project.godot (antes una constante que se quedó en 0.1.0: /health y los
## proyectos guardados decían 0.1.0).
var APP_VERSION: String = ProjectSettings.get_setting("application/config/version", "")
const PROJECT_EXTENSION := "mforge"

func set_grid_size_mm(mm: float) -> void:
	grid_size_m = max(0.001, mm / 1000.0)
	grid_settings_changed.emit()

func grid_size_mm() -> float:
	return grid_size_m * 1000.0

## Ajusta un valor escalar a la rejilla si el snapping está activo.
func snap_scalar(value: float) -> float:
	if not snap_enabled or grid_size_m <= 0.0:
		return value
	return round(value / grid_size_m) * grid_size_m

## Ajusta una posición 3D a la rejilla (en el plano XZ y también en Y).
func snap_vector(v: Vector3) -> Vector3:
	if not snap_enabled:
		return v
	return Vector3(snap_scalar(v.x), snap_scalar(v.y), snap_scalar(v.z))

func notify(text: String, seconds: float = 3.0) -> void:
	status_message.emit(text, seconds)
