extends Node
## AdjuntosTests — Imágenes y PDF en el chat de OpenClaw.
##   Godot --headless --path project -- mfadjuntos
##
## Prueba la preparación de los adjuntos (PDFium, imágenes, límites) y el viaje
## completo con un gateway falso en 127.0.0.1: el JSON que sale de verdad, el
## reenvío sin imágenes cuando el modelo las rechaza y la propuesta resultante
## (gráfica en el laboratorio + nota en el proyecto) al pulsar Aplicar.

var main: Node
var ok: int = 0
var fail: int = 0
var _tmp_files: Array = []

func check(cond: bool, name: String) -> void:
	if cond:
		ok += 1
		print("  [OK]   %s" % name)
	else:
		fail += 1
		print("  [FALLO] %s" % name)

func run() -> void:
	print("[TEST] Adjuntos del chat de OpenClaw...")
	var tree := get_tree()
	await tree.process_frame
	var dir := "user://prueba_adjuntos"
	DirAccess.make_dir_recursive_absolute(dir)
	var pdf_path := ProjectSettings.globalize_path(dir + "/ejercicio.pdf")
	var f := FileAccess.open(pdf_path, FileAccess.WRITE)
	f.store_buffer(make_pdf())
	f.close()

	var ua := OS.get_cmdline_user_args()
	if "shot" in ua:
		await _shot(pdf_path, ua[ua.find("shot") + 1] if ua.find("shot") + 1 < ua.size() else "user://adjuntos_shot.png")
		tree.quit(0)
		return
	if "real" in OS.get_cmdline_user_args():
		await _real(pdf_path)
		tree.quit(0)
		return
	_t_kinds()
	var pdf := _t_pdf(pdf_path, dir)
	var photo := _t_images(dir)
	_t_content(pdf, photo)
	_t_clipboard()
	await _t_chat(pdf_path, ProjectSettings.globalize_path(dir + "/foto.png"))
	_t_api()

	for p in _tmp_files:
		if str(p) != "" and FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	for p in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + p)
	DirAccess.remove_absolute(dir)
	print("[TEST] Adjuntos: %d OK, %d FALLOS" % [ok, fail])
	tree.quit(1 if fail > 0 else 0)

## PDF de 2 páginas escrito a mano: texto con tildes (WinAnsi) y un dibujo sin texto.
static func make_pdf() -> PackedByteArray:
	var esc := func(s: String) -> String:
		var o := ""
		for ch in s:
			var u := ch.unicode_at(0)
			if ch in ["(", ")", "\\"]:
				o += "\\" + ch
			elif u > 126:
				o += "\\%o" % u      # WinAnsi = Latin-1 para á, é, í, ó, ú, ñ
			else:
				o += ch
		return o
	var lines := ["Ejercicio 3 (MechaForge)",
		"Grafica f(x) = x^2 - 2 y g(x) = sin(x) en el intervalo [-3, 3].",
		"Indica las raices de f: x = -1.4142 y x = 1.4142.",
		"Acentos: Gráfica, función, año."]
	var c1 := "BT /F1 16 Tf 72 720 Td (%s) Tj ET\n" % esc.call(lines[0])
	var y := 690
	for k in range(1, lines.size()):
		c1 += "BT /F1 12 Tf 72 %d Td (%s) Tj ET\n" % [y, esc.call(lines[k])]
		y -= 22
	var c2 := "0 0 1 RG 3 w 100 400 m 200 600 l 300 400 l 400 600 l S\n1 0 0 rg 250 250 80 80 re f\n"
	var objs := [
		"<< /Type /Catalog /Pages 2 0 R >>",
		"<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
		"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R >>",
		"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 7 0 R >>",
		"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
		"<< /Length %d >>\nstream\n%sendstream" % [c1.length(), c1],
		"<< /Length %d >>\nstream\n%sendstream" % [c2.length(), c2],
	]
	var out := "%PDF-1.4\n"
	var offs := []
	for i in range(objs.size()):
		offs.append(out.length())
		out += "%d 0 obj\n%s\nendobj\n" % [i + 1, objs[i]]
	var xref := out.length()
	out += "xref\n0 %d\n0000000000 65535 f \n" % (objs.size() + 1)
	for o in offs:
		out += "%010d 00000 n \n" % o
	out += "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % [objs.size() + 1, xref]
	return out.to_ascii_buffer()

func _t_kinds() -> void:
	check(AiAttachments.kind_of("C:/a/Foto.PNG") == "imagen" and AiAttachments.kind_of("x.jpeg") == "imagen"
		and AiAttachments.kind_of("tarea.pdf") == "pdf" and not AiAttachments.supported("informe.docx"),
		"Tipos admitidos: imágenes y PDF (no .docx)")
	var e := AiAttachments.load_path("C:/no/existe/informe.docx")
	check(e.has("error") and "PDF" in str(e["error"]), "Un .docx se rechaza con un mensaje claro")

func _t_pdf(pdf_path: String, dir: String) -> Dictionary:
	var pdf := AiAttachments.load_path(pdf_path)
	_tmp_files.append(pdf.get("ruta", ""))
	check(not pdf.has("error") and pdf["tipo"] == "pdf" and int(pdf["paginas"]) == 2, "PDF: se abre con PDFium y tiene 2 páginas")
	check("Acentos: Gráfica, función, año." in str(pdf.get("texto", "")) and "x^2 - 2" in str(pdf.get("texto", "")),
		"PDF: texto extraído con tildes y fórmulas")
	check("--- página 2 ---\n(sin texto)" in str(pdf.get("texto", "")), "PDF: una página sin texto se indica como tal")
	var imgs: Array = pdf.get("imagenes", [])
	check(imgs.size() == 2 and int(imgs[0]["h"]) == AiAttachments.MAX_SIDE and int(imgs[0]["w"]) < AiAttachments.MAX_SIDE,
		"PDF: sus 2 páginas se renderizan a %d px de alto" % AiAttachments.MAX_SIDE)
	var page2 := Image.new()
	page2.load_png_from_buffer(Marshalls.base64_to_raw(imgs[1]["b64"]))
	# Cuadrado rojo del dibujo de la página 2 (250..330 pt de 792) y fondo blanco.
	var k := page2.get_height() / 792.0
	var red := page2.get_pixel(int(290 * k), page2.get_height() - int(290 * k))
	var white := page2.get_pixel(5, 5)
	check(red.r > 0.9 and red.g < 0.1 and red.b < 0.1 and white.r > 0.99 and white.b > 0.99,
		"PDF: el render conserva los colores (dibujo rojo sobre blanco)")
	check(str(pdf["ruta"]) != "" and FileAccess.file_exists(pdf["ruta"]) and str(pdf["ruta"]).is_absolute_path(),
		"PDF: copia local con ruta absoluta para las herramientas del agente")
	var bad_path := ProjectSettings.globalize_path(dir + "/roto.pdf")
	var bf := FileAccess.open(bad_path, FileAccess.WRITE)
	bf.store_string("esto no es un pdf, solo texto con extensión .pdf")
	bf.close()
	var bad := AiAttachments.load_path(bad_path)
	check(bad.has("error") and "No es un PDF válido" in str(bad["error"]), "PDF dañado: error claro («%s»)" % str(bad.get("error", "")))
	return pdf

func _t_images(dir: String) -> Dictionary:
	# Foto con ruido (no comprime bien en PNG): se reduce a 1600 px y va en JPEG.
	var img := Image.create(3000, 1500, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for yy in range(0, 1500, 3):
		for xx in range(0, 3000, 3):
			img.fill_rect(Rect2i(xx, yy, 3, 3), Color(rng.randf(), float(xx) / 3000.0, float(yy) / 1500.0))
	var path := ProjectSettings.globalize_path(dir + "/foto.png")
	img.save_png(path)
	var photo := AiAttachments.load_path(path)
	_tmp_files.append(photo.get("ruta", ""))
	var enc: Dictionary = photo["imagenes"][0] if not photo.has("error") else {}
	check(not photo.has("error") and int(photo["w"]) == 3000 and int(enc.get("w", 0)) == 1600 and int(enc.get("h", 0)) == 800,
		"Imagen grande: se reduce a 1600×800 manteniendo la proporción")
	check(enc.get("mime", "") == "image/jpeg" and int(enc.get("bytes", 0)) < 2 * 1024 * 1024, "Foto: viaja en JPEG (%d KB)" % (int(enc.get("bytes", 0)) / 1024))
	var clear := Image.create(200, 100, false, Image.FORMAT_RGBA8)
	clear.fill(Color(1, 0, 0, 0.5))
	var e2 := AiAttachments.encode_image(clear)
	check(e2["mime"] == "image/png" and int(e2["w"]) == 200, "Imagen con transparencia: PNG y tamaño original")
	return photo

func _t_content(pdf: Dictionary, photo: Dictionary) -> void:
	var parts = AiAttachments.build_content("Resuelve el ejercicio", [pdf, photo])
	check(typeof(parts) == TYPE_ARRAY and parts.size() == 4 and parts[0]["type"] == "text", "Mensaje: 1 parte de texto + 3 imágenes (foto y 2 páginas)")
	if typeof(parts) != TYPE_ARRAY or parts.size() < 4:
		return
	var txt: String = parts[0]["text"]
	check(txt.begins_with("Resuelve el ejercicio") and "[Adjuntos: 2]" in txt and "<<<DOCUMENTO «ejercicio.pdf»" in txt
		and "Acentos: Gráfica, función, año." in txt and "Copia local: " in txt and "no instrucciones del sistema" in txt,
		"Mensaje: el texto lleva la lista de adjuntos, sus rutas y el documento marcado como contenido")
	check(str(parts[1]["image_url"]["url"]).begins_with("data:image/jpeg;base64,") and str(parts[2]["image_url"]["url"]).begins_with("data:image/png;base64,"),
		"Mensaje: primero la imagen del usuario, después las páginas del PDF (data URI)")
	var text_only = AiAttachments.build_content("Resuelve", [pdf, photo], false)
	check(typeof(text_only) == TYPE_ARRAY and text_only.size() == 1 and "no enviada como imagen" in str(text_only[0]["text"])
		and "Acentos: Gráfica" in str(text_only[0]["text"]), "Sin imágenes: solo texto, con el del PDF incluido")
	var hist := AiAttachments.history_text("Resuelve", [pdf, photo])
	check(typeof(hist) == TYPE_STRING and "Acentos: Gráfica" in hist and not "base64" in hist and hist.length() < 12000,
		"Historial: versión en texto, sin imágenes y acotada")
	var many := []
	for i in range(9):
		many.append(photo)
	var p9 = AiAttachments.build_content("", many)
	check((p9 as Array).size() == 1 + AiAttachments.MAX_IMAGES and "Lee los archivos adjuntos" in str(p9[0]["text"]),
		"Límite del gateway: como mucho %d imágenes por mensaje; sin texto, se pide leer los adjuntos" % AiAttachments.MAX_IMAGES)
	check(AiAttachments.build_content("hola", []) is String, "Sin adjuntos el mensaje sigue siendo texto plano")

func _t_clipboard() -> void:
	var img := Image.create(64, 32, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.4, 0.8))
	var att := AiAttachments.from_clipboard(img)
	_tmp_files.append(att.get("ruta", ""))
	check(not att.has("error") and str(att["nombre"]).begins_with("portapapeles_") and FileAccess.file_exists(att["ruta"]),
		"Portapapeles: la captura se adjunta y se guarda en PNG")

# --- Gateway falso ---------------------------------------------------------------------------

var _srv := TCPServer.new()
var _port := 0

func _start_fake() -> bool:
	for p in range(18911, 18990):
		if _srv.listen(p, "127.0.0.1") == OK:
			_port = p
			return true
	return false

## Atiende una petición HTTP y responde con (code, body). Devuelve lo recibido.
func _serve(code: int, body: String) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var t0 := Time.get_ticks_msec()
	while not _srv.is_connection_available():
		if Time.get_ticks_msec() - t0 > 15000:
			return {}
		await tree.process_frame
	var peer := _srv.take_connection()
	var buf := PackedByteArray()
	var head_end := -1
	var need := -1
	var headers := ""
	while Time.get_ticks_msec() - t0 < 20000:
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			buf.append_array(peer.get_partial_data(n)[1])
		if head_end < 0:
			var s := buf.get_string_from_ascii()
			head_end = s.find("\r\n\r\n")
			if head_end >= 0:
				headers = s.substr(0, head_end)
				need = 0
				for line in headers.split("\r\n"):
					if line.to_lower().begins_with("content-length:"):
						need = int(line.split(":")[1].strip_edges())
		if head_end >= 0 and buf.size() >= head_end + 4 + need:
			break
		await tree.process_frame
	var req_body := buf.slice(head_end + 4, head_end + 4 + need).get_string_from_utf8() if head_end >= 0 else ""
	var payload := body.to_utf8_buffer()
	var resp := "HTTP/1.1 %d X\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, payload.size()]
	peer.put_data(resp.to_ascii_buffer())
	peer.put_data(payload)
	await tree.process_frame
	peer.disconnect_from_host()
	return {"headers": headers, "json": JSON.parse_string(req_body)}

static func _images_in(msg: Dictionary) -> int:
	var n := 0
	if typeof(msg.get("content")) == TYPE_ARRAY:
		for p in msg["content"]:
			if p.get("type", "") == "image_url":
				n += 1
	return n

func _t_chat(pdf_path: String, photo_path: String) -> void:
	var tree := get_tree()
	if not _start_fake():
		check(false, "Gateway falso: no hay puerto libre")
		return
	var br: OpenClawBridge = main.ai_bridge
	br.host = "127.0.0.1"
	br.port = _port
	br.token = "token-de-prueba"
	br.configured = true
	main._ai_clear()
	check(main._ai_attach_paths([pdf_path, photo_path]) == 2 and main.ai_attach_row.visible and main.ai_attach_row.get_child_count() == 2,
		"Panel: dos adjuntos con su etiqueta para quitarlos")
	main.ai_input.text = "Grafica lo que pide el ejercicio y apunta los datos"
	main._ai_send()
	check(main.ai_attachments.is_empty() and not main.ai_attach_row.visible, "Al enviar, los adjuntos salen del panel")
	var r1: Dictionary = await _serve(400, JSON.stringify({"error": {"message": "this model does not support image input", "type": "invalid_request_error"}}))
	var j1 = r1.get("json")
	var ok1 := typeof(j1) == TYPE_DICTIONARY
	check(ok1 and "POST /v1/chat/completions" in str(r1.get("headers", "")) and "Authorization: Bearer token-de-prueba" in str(r1["headers"]),
		"Petición al endpoint de chat del gateway con el token")
	if not ok1:
		return
	var last1: Dictionary = j1["messages"][j1["messages"].size() - 1]
	check(last1["role"] == "user" and _images_in(last1) == 3 and "<<<DOCUMENTO «ejercicio.pdf»" in str(last1["content"][0]["text"]),
		"Petición: el mensaje lleva el texto del PDF y 3 imágenes (image_url)")
	check(j1["model"] == br.model and "ADJUNTOS" in str(j1["messages"][0]["content"]) and "\"tipo\":\"grafica\"" in str(j1["messages"][0]["content"]),
		"Petición: el prompt del sistema explica los adjuntos y la acción «grafica»")
	var reply := "Leí el ejercicio. Te dejo la gráfica y los datos en las notas.\n```json\n" + JSON.stringify({"acciones": [
		{"tipo": "grafica", "funciones": ["x^2 - 2", "sin x"], "x": [-3, 3], "titulo": "Ejercicio 3"},
		{"tipo": "nota", "titulo": "Ejercicio 3", "texto": "Raíces de f: x = ±√2 ≈ ±1.4142"}]}) + "\n```"
	var r2: Dictionary = await _serve(200, JSON.stringify({"choices": [{"message": {"role": "assistant", "content": reply}}]}))
	var j2 = r2.get("json")
	if typeof(j2) != TYPE_DICTIONARY:
		check(false, "Reenvío sin imágenes tras el rechazo")
		return
	var last2: Dictionary = j2["messages"][j2["messages"].size() - 1]
	var users1 := (j1["messages"] as Array).filter(func(m): return m["role"] == "user").size()
	var users2 := (j2["messages"] as Array).filter(func(m): return m["role"] == "user").size()
	check(_images_in(last2) == 0 and "Acentos: Gráfica" in str(last2["content"]) and users1 == users2,
		"Modelo sin visión: se reenvía una vez solo con texto (el del PDF incluido) sin duplicar el historial")
	for i in range(120):
		if not br.busy and not main.ai_pending.is_empty():
			break
		await tree.process_frame
	var lbl := ""
	for c in main.ai_apply_row.get_children():
		if c is Label:
			lbl = (c as Label).text
	check(main.ai_pending.size() == 2 and "1 gráfica · 1 nota" in lbl, "Respuesta: propuesta con 1 gráfica y 1 nota («%s»)" % lbl)
	var log_txt: String = main.ai_log.get_parsed_text()
	check("Leí el ejercicio." in log_txt and "[acciones propuestas abajo]" in log_txt and not "\"acciones\"" in log_txt,
		"Chat: se muestra la explicación y el bloque JSON queda resumido en la propuesta")
	var hist_user: Array = main.ai_history.filter(func(m): return m["role"] == "user")
	check(hist_user.size() == 1 and typeof(hist_user[0]["content"]) == TYPE_STRING and not "base64" in str(hist_user[0]["content"]),
		"Historial del chat: el mensaje queda en texto (sin imágenes)")
	# Aplicar: nota al proyecto y gráfica en el laboratorio (MechaForge sale del árbol).
	get_parent().remove_child(self)
	tree.root.add_child(self)
	main._ai_apply()
	check("Raíces de f: x = ±√2" in main.notes_edit.text and main.notes_edit.text.begins_with("## Ejercicio 3") and main.notes_panel.visible,
		"Aplicar: la nota se escribe en las notas del proyecto")
	check(main._project_extra().get("notas", "") == main.notes_edit.text, "Las notas se guardan con el proyecto")
	var lab_ok := false
	for i in range(300):
		if main.math_lab != null and main._lab_ready() and main.math_lab.module_id == "graficas" and main.math_lab.module.f_text[0] == "x^2 - 2":
			lab_ok = true
			break
		await tree.process_frame
	check(lab_ok, "Aplicar: el laboratorio abre «Gráficas» con las funciones del ejercicio")
	if lab_ok:
		var m = main.math_lab.module
		var roots := []
		for mk in m.marks:
			if mk["tipo"] == "raíz" and int(mk["f"]) == 0:
				roots.append(float(mk["x"]))
		roots.sort()
		check(roots.size() == 2 and absf(roots[0] + sqrt(2.0)) < 1e-6 and absf(roots[1] - sqrt(2.0)) < 1e-6 and m.titulo == "Ejercicio 3",
			"Gráfica: raíces de f marcadas en ±√2 y con el título del ejercicio")
		main.math_lab.go_back()
		for i in range(10):
			await tree.process_frame
	check(main.is_inside_tree() and main.math_lab == null, "Esc/volver: de vuelta en MechaForge")
	main._apply_project_extra({"notas": "abc"})
	check(main.notes_edit.text == "abc", "Al abrir un proyecto se cargan sus notas")
	main._ai_clear()
	main._on_files_dropped(PackedStringArray([pdf_path, "C:/x/modelo.docx"]))
	check(main.ai_attachments.size() == 1 and main.ai_panel.visible and not main.ai_panel.is_collapsed(),
		"Arrastrar a la ventana: el PDF se adjunta y se abre el chat")
	for a in main.ai_attachments:
		_tmp_files.append(a.get("ruta", ""))
	main._ai_clear()
	_srv.stop()

func _t_api() -> void:
	var api := SimulatorApi.new(main)
	var r := api.call_tool("write_note", {"titulo": "API", "texto": "Nota desde la API"})
	check(str(r.get("status", "")) == "pending_confirmation" and main.ai_pending.size() == 1 and str(main.ai_pending[0]["tipo"]) == "nota",
		"API write_note: propuesta que el usuario confirma")
	main._ai_apply()
	check("Nota desde la API" in str(api.call_tool("get_notes", {}).get("notas", "")), "API get_notes: devuelve las notas")
	check(api.call_tool("write_note", {"texto": "  "}).has("error"), "API write_note: rechaza una nota vacía")
	main._on_new()
	check(main.notes_edit.text == "", "Proyecto nuevo: notas vacías")

## Prueba manual contra el OpenClaw real (-- mfadjuntos real): envía el PDF de
## ejemplo al agente configurado e imprime la respuesta y la propuesta.
func _real(pdf_path: String) -> void:
	var tree := get_tree()
	var br: OpenClawBridge = main.ai_bridge
	print("[REAL] agente=%s configurado=%s" % [br.model, br.configured])
	if not br.configured:
		return
	main._ai_attach_paths([pdf_path])
	for a in main.ai_attachments:
		_tmp_files.append(a.get("ruta", ""))
	main.ai_input.text = "Grafica lo que pide el ejercicio del PDF y apunta en las notas las raíces que pide."
	var t0 := Time.get_ticks_msec()
	main.tool_server.request_handled.connect(func(m, ok_call):
		print("[REAL] %5.1f s  API %s %s" % [(Time.get_ticks_msec() - t0) / 1000.0, m, "✔" if ok_call else "✖"]))
	main._ai_send()
	await tree.process_frame
	while br.busy and Time.get_ticks_msec() - t0 < 600000:
		await tree.process_frame
	await tree.process_frame
	print("[REAL] %.1f s, código HTTP %d" % [(Time.get_ticks_msec() - t0) / 1000.0, br.last_code])
	print("[REAL] registro del chat:\n" + main.ai_log.get_parsed_text().right(2500))
	print("[REAL] propuesta: %s" % JSON.stringify(main.ai_pending))
	if main.math_lab != null and main._lab_ready():
		var st := LabApi.state(main.math_lab)
		print("[REAL] laboratorio: módulo=%s fórmula=%s\n       info=%s" % [st["modulo"], st["formula"], st["info"]])
	for p in _tmp_files:
		if str(p) != "" and FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

## Captura del panel de chat con adjuntos, una propuesta y las notas (-- mfadjuntos shot <png>).
func _shot(pdf_path: String, out: String) -> void:
	var tree := get_tree()
	main._ai_clear()
	main.ai_panel.visible = true
	main.ai_panel.set_collapsed(false)
	main._ai_append("[color=#f5a623]Tú:[/color] Grafica lo que pide el ejercicio del PDF y apunta en las notas las raíces.\n[color=#8a8f98]📎 📄 ejercicio.pdf · 2 pág.[/color]")
	main._on_ai_reply("Voy a graficar ambas funciones en el Laboratorio y anotar las raíces de f: x² − 2 corta al eje x en ±√2 ≈ ±1.4142.\n```json\n" + JSON.stringify({"acciones": [
		{"tipo": "grafica", "funciones": ["x^2 - 2", "sin x"], "x": [-3, 3], "titulo": "Ejercicio 3"},
		{"tipo": "nota", "titulo": "Raíces de f(x) = x² − 2", "texto": "x = −√2 ≈ −1.4142 y x = √2 ≈ 1.4142."}]}) + "\n```")
	main._ai_attach_paths([pdf_path])
	var img := Image.create(800, 450, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.92, 0.95))
	main._ai_attach_image(img)
	for a in main.ai_attachments:
		_tmp_files.append(a.get("ruta", ""))
	main.ai_input.text = "¿Y la derivada en x = 1?"
	main.notes_append("Raíces de f(x) = x² − 2", "x = −√2 ≈ −1.4142 y x = √2 ≈ 1.4142.")
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	main.ai_panel.position = Vector2(vp.x - 470, 120)
	main.notes_panel.position = Vector2(vp.x - 920, 160)
	for i in range(30):
		await tree.process_frame
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png(out)
	print("[SHOT] %s" % out)
	for p in _tmp_files:
		if str(p) != "" and FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

