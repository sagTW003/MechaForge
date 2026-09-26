class_name Connection
extends RefCounted
## Connection — Unión entre dos piezas (bisagra, deslizadera, rótula, fija, engranaje).
##
## Es un objeto de datos serializable. La creación real del Joint3D de Godot/Jolt
## la hace el Simulator al entrar en modo simulación.

enum Tipo { FIJA, BISAGRA, DESLIZADERA, ROTULA, ENGRANAJE }

const TIPO_NOMBRE := {
	Tipo.FIJA: "Fija", Tipo.BISAGRA: "Bisagra", Tipo.DESLIZADERA: "Deslizadera",
	Tipo.ROTULA: "Rótula", Tipo.ENGRANAJE: "Engranaje",
}
const AXIS_NOMBRE := ["X", "Y", "Z"]

var uid: String = ""
var a_uid: String = ""
var b_uid: String = ""
var tipo: int = Tipo.BISAGRA
var axis: int = 1                      # 0=X, 1=Y, 2=Z (mundo)
var anchor: Vector3 = Vector3.ZERO     # punto de la unión (mundo)

# Límites (bisagra: radianes; deslizadera: metros).
var limit_enabled: bool = false
var limit_lower: float = -PI
var limit_upper: float = PI

# Motor (solo bisagra). Curva torque–velocidad de motor DC.
var motor_enabled: bool = false
var motor_target_speed: float = 3.0    # rad/s (sentido y magnitud objetivo)
var motor_stall_torque: float = 0.5    # N·m a velocidad 0
var motor_noload_speed: float = 6.0    # rad/s sin carga

# Engranaje: relación de transmisión (ω_b = -ratio * ω_a).
var gear_ratio: float = 1.0

func _init() -> void:
	uid = "c%d_%d" % [Time.get_ticks_usec(), randi() % 100000]

func axis_vector() -> Vector3:
	match axis:
		0: return Vector3.RIGHT
		2: return Vector3.BACK
		_: return Vector3.UP

func tipo_nombre() -> String:
	return TIPO_NOMBRE.get(tipo, "?")

func to_dict() -> Dictionary:
	return {
		"uid": uid, "a": a_uid, "b": b_uid, "tipo": tipo, "axis": axis,
		"anchor": [anchor.x, anchor.y, anchor.z],
		"limit_enabled": limit_enabled, "limit_lower": limit_lower, "limit_upper": limit_upper,
		"motor_enabled": motor_enabled, "motor_target_speed": motor_target_speed,
		"motor_stall_torque": motor_stall_torque, "motor_noload_speed": motor_noload_speed,
		"gear_ratio": gear_ratio,
	}

static func from_dict(d: Dictionary) -> Connection:
	var c := Connection.new()
	c.uid = d.get("uid", c.uid)
	c.a_uid = d.get("a", "")
	c.b_uid = d.get("b", "")
	c.tipo = int(d.get("tipo", Tipo.BISAGRA))
	c.axis = int(d.get("axis", 1))
	var an: Array = d.get("anchor", [0, 0, 0])
	c.anchor = Vector3(an[0], an[1], an[2])
	c.limit_enabled = d.get("limit_enabled", false)
	c.limit_lower = d.get("limit_lower", -PI)
	c.limit_upper = d.get("limit_upper", PI)
	c.motor_enabled = d.get("motor_enabled", false)
	c.motor_target_speed = d.get("motor_target_speed", 3.0)
	c.motor_stall_torque = d.get("motor_stall_torque", 0.5)
	c.motor_noload_speed = d.get("motor_noload_speed", 6.0)
	c.gear_ratio = d.get("gear_ratio", 1.0)
	return c
