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

# --- Control (Fase 3): la bisagra motorizada puede llevar un PID ---
enum ControlMode { NINGUNO, POSICION, VELOCIDAD }
var control_mode: int = ControlMode.NINGUNO
var ctrl_setpoint: float = 0.0   # rad (posición) o rad/s (velocidad)
var ctrl_kp: float = 4.0
var ctrl_ki: float = 0.5
var ctrl_kd: float = 0.2

# --- Eléctrico (Fase 3): consumo del motor como carga ---
var elec_current_noload: float = 0.2   # A en vacío
var elec_current_stall: float = 2.5    # A a par máximo

# --- Integración mecatrónica (Fase F1) ---
## uid del componente eléctrico (motor DC/driver) que alimenta este motor.
## Si está definido, la velocidad/torque escalan con el voltaje del circuito.
var elec_uid: String = ""
var elec_voltaje_nominal: float = 12.0
## Factor de alimentación en tiempo de ejecución (0..1), fijado por el circuito.
var elec_duty: float = 1.0

const CONTROL_NOMBRE := ["Ninguno", "Posición (PID)", "Velocidad (PID)"]

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
		"control_mode": control_mode, "ctrl_setpoint": ctrl_setpoint,
		"ctrl_kp": ctrl_kp, "ctrl_ki": ctrl_ki, "ctrl_kd": ctrl_kd,
		"elec_current_noload": elec_current_noload, "elec_current_stall": elec_current_stall,
		"elec_uid": elec_uid, "elec_voltaje_nominal": elec_voltaje_nominal,
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
	c.control_mode = int(d.get("control_mode", ControlMode.NINGUNO))
	c.ctrl_setpoint = d.get("ctrl_setpoint", 0.0)
	c.ctrl_kp = d.get("ctrl_kp", 4.0)
	c.ctrl_ki = d.get("ctrl_ki", 0.5)
	c.ctrl_kd = d.get("ctrl_kd", 0.2)
	c.elec_current_noload = d.get("elec_current_noload", 0.2)
	c.elec_current_stall = d.get("elec_current_stall", 2.5)
	c.elec_uid = d.get("elec_uid", "")
	c.elec_voltaje_nominal = d.get("elec_voltaje_nominal", 12.0)
	return c
