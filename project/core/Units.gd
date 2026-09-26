class_name Units
extends RefCounted
## Units — Utilidades de unidades SI y formateo legible.
##
## Toda la lógica interna de MechaForge usa unidades SI (m, kg, s, N, ...).
## Estas funciones sirven solo para MOSTRAR valores al usuario en la UI.

static func fmt_length(meters: float) -> String:
	var mm := meters * 1000.0
	if absf(mm) < 10.0:
		return "%.2f mm" % mm
	elif absf(meters) < 1.0:
		return "%.1f mm" % mm
	else:
		return "%.3f m" % meters

static func fmt_mass(kg: float) -> String:
	if absf(kg) < 1.0:
		return "%.1f g" % (kg * 1000.0)
	return "%.3f kg" % kg

static func fmt_force(newtons: float) -> String:
	return "%.2f N" % newtons

static func fmt_torque(nm: float) -> String:
	return "%.3f N·m" % nm

static func fmt_speed(mps: float) -> String:
	return "%.2f m/s" % mps

static func fmt_angle(rad: float) -> String:
	return "%.1f°" % rad_to_deg(rad)

static func fmt_volume_cm3(m3: float) -> String:
	return "%.1f cm³" % (m3 * 1_000_000.0)
