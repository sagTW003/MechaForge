class_name HeadsetCheck
extends RefCounted
## HeadsetCheck — Verificación óptica y ergonomía del visor casero.
##
## Óptica (por ojo): el render dibuja lo que su cámara ve en la dirección t en el punto
## de la pantalla P = c_r + undistort_r(t) / s_r (lo que SUPONE el perfil del render);
## el ojo del usuario ve ese punto, a través de la lente REAL, en
##   t' = D(s·(P − c) − c_ojo / L)
## (c el eje real de la lente, s su escala, D su distorsión; c_ojo lo que el ojo está
## fuera del eje y L la distancia de la imagen virtual al ojo). De t' frente a t salen:
##   · la desalineación de la imagen (t' del punto que debería verse de frente);
##   · la distorsión residual (lo que queda quitando esa desalineación) y su valor en el
##     borde: + cojín, − barril;
##   · la aberración cromática residual (separación entre el rojo y el azul).
## Con los dos ojos, la diferencia de las desalineaciones es lo que los ojos tienen que
## converger (o divergir, que tolera mucho peor) o desnivelar para fundir las imágenes,
## en minutos de arco y en dioptrías prismáticas (Δ = 100·tan θ).
##
## Ergonomía: masa del visor (sin la cabeza de prueba), su centro de masa respecto del
## apoyo en la cara (frente y puente de la nariz, FACE_OFFSET por delante de los ojos) y
## el par que tira de la cara hacia delante.
## Holguras: de cada lente a la pantalla y a las pestañas, y los contactos o
## interferencias entre las piezas del visor (distancia entre sus formas de colisión).

const FACE_OFFSET := 0.012         # frente y puente de la nariz, por delante de los ojos (m)
const G0 := 9.80665
const EYELASH_MIN := 0.008          # holgura mínima de las pestañas (m)
const NEAR_GAP := 0.003             # se informan los pares de piezas a menos de esto
const CONTACT_TOL := 0.0003

static func report(main: Node, rig: HeadsetRig) -> Dictionary:
	var lay: Dictionary = rig.layout
	if not lay.get("ok", false):
		lay = HeadsetRig.compute_layout(main.parts_root, Callable(main, "_part_live_xform"), 1.0, rig.render_profile())
	if not lay.get("ok", false):
		return {"ok": false, "motivo": str(lay.get("motivo", "Hace falta una pantalla con sus lentes."))}
	var opt := optical(lay, rig.user_ipd_mm / 1000.0, rig.predistort, rig.chroma)
	var erg := ergonomics(main, lay)
	var clr := clearances(main, lay)
	var avisos: Array = []
	avisos.append_array(opt["avisos"])
	avisos.append_array(erg["avisos"])
	avisos.append_array(clr["avisos"])
	return {"ok": true, "perfil": HeadsetRig.PROFILE_NAMES[rig.profile_mode], "perfil_valores": rig.render_profile(),
		"ipd_usuario_mm": rig.user_ipd_mm, "optica": opt, "ergonomia": erg, "holguras": clr, "avisos": avisos}

#region ÓPTICA --------------------------------------------------------------------

## Ángulo (minutos de arco) entre las direcciones (a, 1) y (b, 1): atan2(|a×b|, a·b) en
## doble precisión (acos de un producto escalar en float32 da errores de ~2′).
static func _arcmin(a: Vector2, b: Vector2) -> float:
	var ax := float(a.x)
	var ay := float(a.y)
	var bx := float(b.x)
	var by := float(b.y)
	var cx := ay - by
	var cy := bx - ax
	var cz := ax * by - ay * bx
	return rad_to_deg(atan2(sqrt(cx * cx + cy * cy + cz * cz), ax * bx + ay * by + 1.0)) * 60.0

## Dónde ve el ojo i (dirección t') lo que el render puso en la dirección tc, canal ch;
## devuelve [t', P] con P el punto de la pantalla (m, coordenadas del espectador).
static func seen(lay: Dictionary, i: int, tc: Vector2, ch: int, user_ipd_m: float, predist := true, chrom := true) -> Array:
	var e: Dictionary = lay["eyes"][i]
	var ph: Dictionary = e["fisico"]
	var k_r: Vector2 = e["k"] if predist else Vector2.ZERO
	var cs_r: float = (e["cromatica"] as Vector3)[ch] if chrom else 1.0
	var p: Vector2 = (e["centro"] as Vector2) + Optics.undistort(tc, k_r.x, k_r.y) / (float(e["escala"]) * cs_r)
	var tl: Vector2 = (p - (ph["centro"] as Vector2)) * float(ph["escala"]) * (ph["cromatica"] as Vector3)[ch] \
		- HeadsetRig.eye_shift(lay, i, user_ipd_m)
	return [Optics.distort(tl, ph["k"].x, ph["k"].y), p]

## Errores de un ojo sobre una rejilla del campo del render (puntos que el ojo ve).
static func eye_residual(lay: Dictionary, i: int, user_ipd_m: float, predist := true, chrom := true) -> Dictionary:
	var e: Dictionary = lay["eyes"][i]
	var ph: Dictionary = e["fisico"]
	var ta: float = ph["ta"]
	var hx: Vector2 = ph["mitad_x"]
	var ah: float = (lay["area"] as Vector2).y * 0.5
	var t0: Vector2 = seen(lay, i, Vector2.ZERO, 1, user_ipd_m, predist, chrom)[0]
	var tans: Vector4 = e["tans"]
	var n := 25
	var ss := 0.0
	var mx := 0.0
	var cmax := 0.0
	var cnt := 0
	var edge_r := -1.0
	var edge_pct := 0.0
	for a in range(n):
		for b in range(n):
			var tc := Vector2(lerpf(tans.x, tans.y, a / float(n - 1)), lerpf(tans.z, tans.w, b / float(n - 1)))
			var sg := seen(lay, i, tc, 1, user_ipd_m, predist, chrom)
			var te: Vector2 = sg[0]
			var p: Vector2 = sg[1]
			if p.x < hx.x or p.x > hx.y or absf(p.y) > ah or te.length() > ta:
				continue
			var err := _arcmin(te, tc + t0)
			ss += err * err
			mx = maxf(mx, err)
			cnt += 1
			if tc.length() > edge_r and tc.length() > 1e-3:
				edge_r = tc.length()
				edge_pct = ((te - t0).length() - tc.length()) / tc.length() * 100.0
			var tr: Vector2 = seen(lay, i, tc, 0, user_ipd_m, predist, chrom)[0]
			var tb: Vector2 = seen(lay, i, tc, 2, user_ipd_m, predist, chrom)[0]
			cmax = maxf(cmax, _arcmin(tr, tb))
	var ft: Vector4 = ph["tans"]
	return {
		"lado": e["lado"],
		"desalineacion_h_arcmin": rad_to_deg(atan(t0.x)) * 60.0, "desalineacion_v_arcmin": rad_to_deg(atan(t0.y)) * 60.0,
		"distorsion_rms_arcmin": sqrt(ss / cnt) if cnt > 0 else 0.0, "distorsion_max_arcmin": mx,
		"distorsion_borde_pct": edge_pct, "cromatica_max_arcmin": cmax, "muestras": cnt,
		"campo_h_deg": rad_to_deg(atan(ft.y) - atan(ft.x)), "campo_v_deg": rad_to_deg(atan(ft.w) - atan(ft.z)),
	}

static func _prism(arcmin: float) -> float:
	return 100.0 * tan(deg_to_rad(arcmin / 60.0))

static func optical(lay: Dictionary, user_ipd_m: float, predist := true, chrom := true) -> Dictionary:
	var eyes := []
	var avisos := []
	for i in range((lay["eyes"] as Array).size()):
		var r := eye_residual(lay, i, user_ipd_m, predist, chrom)
		eyes.append(r)
		var nom := "Ojo %s" % str(r["lado"]) if lay["estereo"] else "La imagen"
		if float(r["distorsion_max_arcmin"]) > 30.0:
			avisos.append("%s: distorsión residual de hasta %.0f′ (%+.1f %% en el borde, %s): las rectas se ven curvas; ajusta k1 y k2 del perfil a la lente." % [
				nom, r["distorsion_max_arcmin"], r["distorsion_borde_pct"], "cojín" if float(r["distorsion_borde_pct"]) > 0.0 else "barril"])
		if float(r["cromatica_max_arcmin"]) > 4.0:
			avisos.append("%s: el rojo y el azul se separan hasta %.1f′ en el borde (aberración cromática sin corregir)." % [nom, r["cromatica_max_arcmin"]])
	var out := {"ojos": eyes, "avisos": avisos}
	if lay["estereo"] and eyes.size() == 2:
		var h := float(eyes[0]["desalineacion_h_arcmin"]) - float(eyes[1]["desalineacion_h_arcmin"])
		var v := float(eyes[0]["desalineacion_v_arcmin"]) - float(eyes[1]["desalineacion_v_arcmin"])
		var ph := _prism(h)
		var pv := _prism(v)
		out["convergencia_arcmin"] = h
		out["convergencia_prisma"] = ph
		out["vertical_arcmin"] = v
		out["vertical_prisma"] = pv
		var ipd_lens := absf(float(lay["eyes"][0]["fisico"]["centro"].x) - float(lay["eyes"][1]["fisico"]["centro"].x))
		var ipd_render := absf(float(lay["eyes"][0]["centro"].x) - float(lay["eyes"][1]["centro"].x))
		out["ipd_lentes_mm"] = ipd_lens * 1000.0
		out["ipd_render_mm"] = ipd_render * 1000.0
		out["ipd_usuario_mm"] = user_ipd_m * 1000.0
		if ph < -1.0:
			avisos.append("Los ojos tendrían que divergir %.1f Δ para fundir las imágenes (se tolera menos de 1 Δ): ajusta la IPD del render o de las lentes a la del usuario." % -ph)
		elif ph > 4.0:
			avisos.append("Los ojos tendrían que converger %.1f Δ para fundir las imágenes (cansa por encima de unos 4 Δ)." % ph)
		if absf(pv) > 0.5:
			avisos.append("Desnivel vertical de %.2f Δ entre las dos imágenes (se tolera hasta unos 0.5 Δ): visión doble." % absf(pv))
	return out

#endregion

#region ERGONOMÍA ----------------------------------------------------------------

## Posición real (en el mundo) del ojo i: sobre el eje de su lente, a e de ella.
static func physical_eye(main: Node, lay: Dictionary, i: int) -> Vector3:
	var scr: PartInstance = main._find_part(str(lay["screen_uid"]))
	var sx: Transform3D = main._part_live_xform(scr)
	var ph: Dictionary = lay["eyes"][i]["fisico"]
	var c: Vector2 = ph["centro"]
	var front := PartLibrary.dims_m(scr.def).y * 0.5
	return sx * Vector3(-c.x, front + float(ph["d_m"]) + float(ph["e_m"]), c.y)

static func ergonomics(main: Node, lay: Dictionary) -> Dictionary:
	var hid := HeadsetRig.hidden_parts(main, lay)
	var mass := 0.0
	var acc := Vector3.ZERO
	var count := 0
	for uid in hid:
		var p: PartInstance = main._find_part(str(uid))
		if p == null or str(p.def.get("forma", "")) == "cabeza":
			continue
		var m := p.mass_kg()
		acc += (main._part_live_xform(p) * p.com_local()) * m
		mass += m
		count += 1
	var avisos := []
	if mass <= 0.0:
		return {"masa_g": 0.0, "avisos": avisos}
	var com := acc / mass
	var scr: PartInstance = main._find_part(str(lay["screen_uid"]))
	var sb: Basis = main._part_live_xform(scr).basis
	var fwd := -sb.y.normalized()
	var up := sb.z.normalized()
	var mid := Vector3.ZERO
	var ne := (lay["eyes"] as Array).size()
	for i in range(ne):
		mid += physical_eye(main, lay, i)
	mid /= ne
	var face := mid + fwd * FACE_OFFSET
	var dfwd := (com - face).dot(fwd)
	var h := (com - mid).dot(up)
	var torque := mass * G0 * dfwd
	var vm := "ligero" if mass <= 0.35 else ("aceptable" if mass <= 0.55 else "pesado")
	var vt := "bien equilibrado" if torque <= 0.15 else ("aceptable" if torque <= 0.35 else "cargado hacia delante")
	if mass > 0.55:
		avisos.append("El visor pesa %.0f g: por encima de unos 550 g cansa el cuello (los comerciales rondan los 500 g)." % (mass * 1000.0))
	if torque > 0.35:
		avisos.append("Par de %.2f N·m hacia delante sobre la cara (centro de masa %.0f mm por delante): acerca la electrónica a la cara o pon un contrapeso atrás." % [torque, dfwd * 1000.0])
	return {"masa_g": mass * 1000.0, "piezas": count, "centro_masa": [com.x, com.y, com.z],
		"delante_de_la_cara_mm": dfwd * 1000.0, "altura_sobre_ojos_mm": h * 1000.0, "par_Nm": torque,
		"valoracion_masa": vm, "valoracion_par": vt, "avisos": avisos}

#endregion

#region HOLGURAS -----------------------------------------------------------------

static func clearances(main: Node, lay: Dictionary) -> Dictionary:
	var avisos := []
	var lenses := []
	for e in lay["eyes"]:
		var lens: PartInstance = main._find_part(str(e["uid"]))
		if lens == null:
			continue
		var t := float(PartLibrary.lens_geometry(lens.def)["t"])
		var ph: Dictionary = e["fisico"]
		var gs := float(ph["d_m"]) - t * 0.5
		var gl := float(ph["e_m"]) - t * 0.5
		lenses.append({"lado": e["lado"], "lente_pantalla_mm": gs * 1000.0, "pestanas_mm": gl * 1000.0})
		var nom := "La lente %s" % str(e["lado"]) if lay["estereo"] else "La lente"
		if gs < 0.002:
			avisos.append("%s está a %.1f mm de la pantalla: casi la toca." % [nom, gs * 1000.0])
		if gl < EYELASH_MIN:
			avisos.append("%s deja %.1f mm a las pestañas (mínimo unos %.0f mm): rozarían la lente." % [nom, gl * 1000.0, EYELASH_MIN * 1000.0])
	# Pares de piezas del visor cerca o en contacto.
	var hid := HeadsetRig.hidden_parts(main, lay)
	var parts := []
	for uid in hid:
		var p: PartInstance = main._find_part(str(uid))
		if p and str(p.def.get("forma", "")) != "cabeza":
			parts.append(p)
	var names := {}
	for e in lay["eyes"]:
		names[str(e["uid"])] = "lente %s" % str(e["lado"])
	var sliders := {}
	for c in main.connections:
		var conn := c as Connection
		if conn.tipo == Connection.Tipo.DESLIZADERA:
			sliders[conn.a_uid + "|" + conn.b_uid] = true
			sliders[conn.b_uid + "|" + conn.a_uid] = true
	var shapes := {}
	for p in parts:
		shapes[(p as PartInstance).uid] = _world_shapes(main, p)
	var pairs := []
	for a in range(parts.size()):
		for b in range(a + 1, parts.size()):
			var pa: PartInstance = parts[a]
			var pb: PartInstance = parts[b]
			var gap := shapes_gap(shapes[pa.uid], shapes[pb.uid])
			if gap >= NEAR_GAP:
				continue
			var na: String = names.get(pa.uid, str(pa.def.get("nombre", pa.def_id)))
			var nb: String = names.get(pb.uid, str(pb.def.get("nombre", pb.def_id)))
			var estado := "holgura"
			if sliders.has(pa.uid + "|" + pb.uid) and gap < CONTACT_TOL:
				estado = "en su guía"
			elif gap < -CONTACT_TOL:
				estado = "interferencia"
				avisos.append("Interferencia de %.1f mm entre %s y %s: no caben así." % [-gap * 1000.0, na, nb])
			elif gap <= CONTACT_TOL:
				estado = "en contacto"
			pairs.append({"a": na, "b": nb, "holgura_mm": gap * 1000.0, "estado": estado})
	return {"lentes": lenses, "pares": pairs, "avisos": avisos}

## Formas de colisión de una pieza en el mundo: [{shape, xf}].
static func _world_shapes(main: Node, p: PartInstance) -> Array:
	var px: Transform3D = main._part_live_xform(p)
	var out := []
	for sd in p.make_collision_shapes():
		out.append({"shape": sd["shape"], "xf": px * (sd["xf"] as Transform3D)})
	return out

## Distancia entre dos piezas (m): la menor distancia con signo de los puntos de la
## superficie de cada una a las formas de la otra (negativa = se meten una en otra).
static func shapes_gap(sa: Array, sb: Array) -> float:
	var best := INF
	for pair in [[sa, sb], [sb, sa]]:
		var src: Array = pair[0]
		var dst: Array = pair[1]
		var inv := []
		for d in dst:
			inv.append((d["xf"] as Transform3D).affine_inverse())
		for s in src:
			for pt in _samples(s["shape"]):
				var w: Vector3 = (s["xf"] as Transform3D) * (pt as Vector3)
				for j in range(dst.size()):
					best = minf(best, sdf(dst[j]["shape"], (inv[j] as Transform3D) * w))
	return best

## Puntos de la superficie de una forma (en su espacio).
static func _samples(shape: Shape3D) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var n := 6
	if shape is BoxShape3D:
		var h := (shape as BoxShape3D).size * 0.5
		for ax in range(3):
			for sgn in [-1.0, 1.0]:
				for i in range(n + 1):
					for j in range(n + 1):
						var u := lerpf(-1.0, 1.0, i / float(n))
						var v := lerpf(-1.0, 1.0, j / float(n))
						var q := Vector3.ZERO
						q[ax] = sgn
						q[(ax + 1) % 3] = u
						q[(ax + 2) % 3] = v
						pts.append(q * h)
	elif shape is CylinderShape3D:
		var r := (shape as CylinderShape3D).radius
		var hh := (shape as CylinderShape3D).height * 0.5
		for k in range(16):
			var a := TAU * k / 16.0
			for y in [-hh, -hh * 0.33, hh * 0.33, hh]:
				pts.append(Vector3(cos(a) * r, y, sin(a) * r))
			for rr in [r * 0.33, r * 0.66]:
				pts.append(Vector3(cos(a) * rr, hh, sin(a) * rr))
				pts.append(Vector3(cos(a) * rr, -hh, sin(a) * rr))
	elif shape is ConvexPolygonShape3D:
		pts = (shape as ConvexPolygonShape3D).points
	return pts

## Distancia con signo de un punto (espacio de la forma) a la forma: caja y cilindro
## exactos; una forma convexa, por su caja envolvente.
static func sdf(shape: Shape3D, p: Vector3) -> float:
	if shape is BoxShape3D:
		return _sdf_box(p, (shape as BoxShape3D).size * 0.5)
	if shape is CylinderShape3D:
		var c := shape as CylinderShape3D
		var d := Vector2(Vector2(p.x, p.z).length() - c.radius, absf(p.y) - c.height * 0.5)
		return minf(maxf(d.x, d.y), 0.0) + Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()
	if shape is ConvexPolygonShape3D:
		var aabb := AABB()
		var first := true
		for q in (shape as ConvexPolygonShape3D).points:
			if first:
				aabb = AABB(q, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(q)
		return _sdf_box(p - aabb.get_center(), aabb.size * 0.5)
	return INF

static func _sdf_box(p: Vector3, h: Vector3) -> float:
	var q := p.abs() - h
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)

#endregion

#region TEXTO ----------------------------------------------------------------------

## Cero limpio para el texto (sin «−0.0»).
static func _z(x: float, eps := 0.05) -> float:
	return 0.0 if absf(x) < eps else x

## Informe para el panel (BBCode).
static func report_bbcode(r: Dictionary) -> String:
	if not r.get("ok", false):
		return "[color=#a0a4ab]%s[/color]" % str(r.get("motivo", ""))
	var t := ""
	var o: Dictionary = r["optica"]
	t += "[b]Óptica[/b] · perfil del render: %s\n" % str(r["perfil"])
	for e in o["ojos"]:
		t += "  Ojo %s: imagen desalineada %+.0f′ / %+.0f′ (h/v) · distorsión residual %.1f′ RMS, máx %.1f′ (%+.1f %% en el borde) · color %.1f′ · campo %.0f° × %.0f°\n" % [
			e["lado"], _z(e["desalineacion_h_arcmin"], 0.5), _z(e["desalineacion_v_arcmin"], 0.5), e["distorsion_rms_arcmin"],
			e["distorsion_max_arcmin"], _z(e["distorsion_borde_pct"]), e["cromatica_max_arcmin"], e["campo_h_deg"], e["campo_v_deg"]]
	if o.has("convergencia_prisma"):
		var ph := float(o["convergencia_prisma"])
		t += "  Dos ojos: %s %.2f Δ (%.0f′) · desnivel vertical %.2f Δ · IPD: lentes %.1f mm, render %.1f mm, usuario %.1f mm\n" % [
			"convergencia" if ph >= 0.0 else "divergencia", absf(ph), absf(float(o["convergencia_arcmin"])),
			absf(float(o["vertical_prisma"])), o["ipd_lentes_mm"], o["ipd_render_mm"], o["ipd_usuario_mm"]]
	var g: Dictionary = r["ergonomia"]
	t += "[b]Ergonomía[/b]\n  %.0f g (%s) · centro de masa %.0f mm por delante de la cara y %+.0f mm sobre los ojos · par %.2f N·m (%s)\n" % [
		g.get("masa_g", 0.0), g.get("valoracion_masa", ""), g.get("delante_de_la_cara_mm", 0.0), _z(g.get("altura_sobre_ojos_mm", 0.0), 0.5),
		g.get("par_Nm", 0.0), g.get("valoracion_par", "")]
	var h: Dictionary = r["holguras"]
	t += "[b]Holguras[/b]\n"
	for l in h["lentes"]:
		t += "  Lente %s: %.1f mm a la pantalla, %.1f mm a las pestañas\n" % [l["lado"], l["lente_pantalla_mm"], l["pestanas_mm"]]
	for p in h["pares"]:
		var col := "#ff8a5c" if str(p["estado"]) == "interferencia" else "#a0a4ab"
		t += "  [color=%s]%s – %s: %s (%.1f mm)[/color]\n" % [col, p["a"], p["b"], p["estado"], _z(p["holgura_mm"])]
	if (r["avisos"] as Array).is_empty():
		t += "[color=#7ee08a]Sin avisos.[/color]"
	else:
		for a in r["avisos"]:
			t += "[color=#ffb75a]⚠ %s[/color]\n" % str(a)
	return t

#endregion
