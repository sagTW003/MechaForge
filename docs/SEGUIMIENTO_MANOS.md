# Seguimiento de manos en el Laboratorio matemático

Permite manejar el Laboratorio con las manos delante de la webcam: apuntar,
girar gráficas, arrastrar deslizadores, pulsar botones, hacer zoom con las dos
manos y pausar con la palma abierta.

Se activa con el botón **🖐 Manos** de la barra superior del Laboratorio o con la
tecla **H**.

## Requisitos

- Una webcam. Tiene que estar libre: si otra aplicación la usa, por ejemplo el
  seguimiento de manos del HUD «Viernes», ciérrala antes.
- Python 3 con los paquetes de `tools/handtracking/requirements.txt`:

  ```bash
  python -m pip install -r tools/handtracking/requirements.txt
  ```

- El modelo `tools/handtracking/models/hand_landmarker.task` (MediaPipe
  HandLandmarker, licencia Apache 2.0) ya va incluido.
- En Windows: *Configuración > Privacidad y seguridad > Cámara >* permitir que las
  aplicaciones de escritorio usen la cámara.

## Arquitectura (tres capas)

```
 webcam ─► mf_hands.py (proceso aparte)                         Godot (MechaForge)
           ├ hilo de captura: guarda solo el último fotograma
           ├ MediaPipe HandLandmarker (VIDEO, 2 manos)
           └ UDP 127.0.0.1:18791, JSON + token ───────► HandTracker.gd        capa 1
                                                         │ One Euro × 21 puntos × 2 manos
                                                         ▼
                                                        GestureRecognizer.gd  capa 2
                                                         │ gestos, histéresis, antirrebote
                                                         ▼
                                                        VirtualLabController.gd capa 3
                                                          cursor, clics, giro, zoom, HUD
```

| Capa | Archivo | Qué hace |
|---|---|---|
| Captura | `tools/handtracking/mf_hands.py` | Abre la cámara (DirectShow/MSMF, MJPG, búfer de 1) e infiere con MediaPipe. La imagen va en espejo y la inferencia corre en su propio proceso, así nunca frena el render. Envía los 21 puntos de cada mano, en coordenadas de imagen y métricas, más el tiempo de captura y de inferencia. |
| HandTracker | `project/handtracking/HandTracker.gd` | Lanza y cierra el proceso y escucha solo en 127.0.0.1, validando el token. Pasa cada coordenada por un filtro One Euro, publica `hands` y mide los fps y la latencia. |
| GestureRecognizer | `project/handtracking/GestureRecognizer.gd` | Máquina de estados por mano: apuntar, pellizco, palma y reposo. Aplica histéresis y antirrebote, gestiona la zona de interacción y el zoom con dos manos. |
| VirtualLabController | `project/handtracking/VirtualLabController.gd` | Traduce los gestos al Laboratorio: cursor, inyección de clics en la interfaz, cámara. Incluye el HUD y el panel de ajustes. |
| Filtro | `project/handtracking/OneEuroFilter.gd` | One Euro Filter: corte = corte_mín + β·\|velocidad\|. |

**Rendimiento medido en este equipo (CPU):**
- inferencia ≈ 10.7 ms por fotograma sin manos (detección de palma) y menos
  cuando ya sigue una mano;
- el transporte por UDP local es inferior a 1 ms.

La latencia total que muestra el HUD va desde la captura hasta Godot. La tasa de
fotogramas la limita la cámara: la mayoría dan 30 fps y algunas 60 fps en MJPG a
640×480.

## Gestos

| Gesto | Cómo | Acción en el Laboratorio |
|---|---|---|
| ☝ **Apuntar** | Índice extendido, resto cerrados | Mueve el cursor. Sobre la escena 3D aparece el tooltip con coordenadas y valores; sobre la interfaz, los controles se resaltan. |
| 🤏 **Pellizco** | Pulgar e índice juntos (< 3 cm) | Depende de dónde esté el cursor (ver abajo). |
| 🤏🤏 **Dos pellizcos** | Pellizcar con ambas manos | Zoom: separarlas acerca la cámara. |
| ✊✊ **Dos puños** | Cerrar las dos manos | Agarra la escena y la mueve en 3D. |
| 🖐 **Palma abierta** | Cinco dedos extendidos y separados | Congela la interacción mientras se mantiene. Pasado 1 s, reinicia la vista del módulo (anillo de progreso en el cursor). |

Qué hace el pellizco según dónde esté el cursor:

| Sobre… | Acción |
|---|---|
| Un deslizador | **Ajuste fino**: la mano recorre ×3 el ancho del control para todo el rango. |
| Botones, casillas, desplegables | Clic. |
| La gráfica 3D | Giro orbital. |
| Una gráfica 2D (vista superior, módulos de tablero) | Desplazamiento (pan). |
| La escena, con «✋ Perturbar» activa | Perturba la escena: pulsos, calor, barreras… |

**Zoom con dos pellizcos:** la distancia de la cámara se multiplica por
ratio^(−sensibilidad), con sensibilidad 1,8 por defecto. Por ejemplo, separar las
manos al doble acerca la cámara ×3,5, más que el 1:1 anterior. Los cambios
minúsculos del temblor se acumulan en una zona muerta, así la vista no «respira».

**Dos puños:** al cerrar las dos manos se agarra la escena, que se mueve con ellas:
- **trasladar**: mover las dos manos arrastra la escena en el plano de la pantalla;
- **profundidad**: acercar las manos a la cámara, que se ven más grandes, la trae
  hacia uno; alejarlas la aleja;
- **rotar**: girar la línea entre los dos puños, como un volante, la gira sobre el
  eje vertical. Se desactiva en el panel.

Un puño solo no hace nada, igual que el reposo. El agarre termina al abrir una de
las manos.

**Detalle del pellizco:**
- **Medidor** junto al cursor: una barra de 0 a 8 cm con la zona de activación
  (naranja, hasta 3 cm) y la de histéresis (amarilla, hasta 4,5 cm), la distancia
  actual pulgar–índice y la fase: *acercando*, *cerrando*, *activo* o *soltando*.
- En el minimapa, la línea pulgar–índice de cada mano se colorea con esa fase.
- **Precisión adaptativa**: la ganancia sube de 0,35 a 1 según la velocidad de la
  mano (de 120 a 900 px/s), como la aceleración de un ratón. Mover la mano despacio
  da un ajuste fino de giros, desplazamientos y deslizadores; moverla deprisa
  recorre mucho. El HUD muestra la ganancia en uso («precisión ×0.36»).

**Ergonomía:**
- **Zona de interacción**: un rectángulo de la imagen de la cámara, por defecto
  centrado y a la altura del pecho, se estira a toda la pantalla. No hace falta
  levantar el brazo («brazo de gorila»). Su tamaño y altura se ajustan en el panel.
- **Histéresis**: el pellizco se activa por debajo de 3 cm y solo se suelta por
  encima de 4,5 cm. Los dedos «extendidos» usan umbrales distintos para entrar y
  salir.
- **Antirrebote**: un gesto nuevo debe mantenerse 50 ms.
- **Cursor sin saltos**: al pasar de apuntar (punta del índice) a pellizcar (punto
  medio pulgar–índice), el cursor conserva su posición.
- **Palma abierta**: sirve de «zona muerta» temporal para recolocar la mano sin
  mover nada.
- Solo la **mano principal**, derecha por defecto, mueve el cursor. La otra se usa
  para el zoom.

## Panel «✋ Seguimiento de manos»

- Mano principal.
- Tamaño y altura de la zona de interacción.
- Umbrales del pellizco.
- Suavizado (corte mínimo del One Euro) y reactividad (β).
- Sensibilidad de giro y factor del ajuste fino.
- Precisión adaptativa y su ganancia en movimientos lentos.
- Sensibilidad del zoom.
- Sensibilidad de los dos puños y giro de «volante».
- Mostrar el esqueleto y mover el puntero del ratón.

El HUD (abajo a la derecha) muestra:
- la imagen de la cámara reducida a esqueleto;
- la zona de interacción y el gesto de cada mano;
- fps, latencia e inferencia.

El punto rojo indica que **la cámara está activa**.

La configuración se guarda en `%APPDATA%\Godot\app_userdata\MechaForge\mechaforge_hands.json`:
- `python`: ruta del intérprete si no es `python`;
- `camera`: -1 prueba de 0 a 3;
- `port`, `width`, `height`, `fps`;
- `token`: se genera solo;
- ajustes.

## Enlazar los eventos en código

Las señales de `GestureRecognizer` corresponden a los eventos del diseño:

| Señal (GDScript) | Evento | Argumentos |
|---|---|---|
| `pointed` | `onPoint` | `hand: String, pos: Vector2` (pantalla en [0, 1]²) |
| `pinch_started` | `onPinchStart` | `hand, pos` |
| `pinch_moved` | `onPinchMove` | `hand, pos, delta` |
| `pinch_ended` | `onPinchEnd` | `hand, pos, cancelled` (true si lo anuló el zoom de dos manos) |
| `zoom_started` / `zoom_changed` / `zoom_ended` | `onZoomStart/Move/End` | `zoom_changed(ratio_del_fotograma, ratio_total)` |
| `palm_started` / `palm_held` / `palm_reset` / `palm_ended` | `onPalm…` | `palm_held(hand, progreso 0–1)` |
| `grab_started` / `grab_moved` / `grab_ended` | `onGrabStart/Move/End` | `grab_moved(delta: Vector3, ángulo)`: delta.x, delta.y en pantalla [0, 1]; delta.z = ln(escala), positivo al acercar las manos a la cámara |
| `pinch_phase(hand)` | — | «lejos», «acercando», «cerrando», «activo» o «soltando» (función, no señal) |
| `gesture_changed`, `hand_lost` | — | cambios de estado por mano |

Ejemplo: en un módulo, que el pellizco cambie la constante k de `f(x) = k·x²`:

```gdscript
func _ready() -> void:
	var rec: GestureRecognizer = lab.hands.recognizer
	rec.pinch_started.connect(func(hand, pos): _k0 = k)
	rec.pinch_moved.connect(func(hand, pos, delta):
		k = _k0 + (pos.x - 0.5) * 4.0      # la mano en horizontal recorre k ∈ [k₀ − 2, k₀ + 2]
		_rebuild())
	rec.palm_reset.connect(func(hand): k = 1.0; _rebuild())
```

La cámara del Laboratorio se maneja con `lab.cam.orbit(dx, dy)`, `lab.cam.pan(dx, dy)`,
`lab.cam.zoom(factor)` y `lab.reset_view()`.

Para otra escena de Godot, instancia `HandTracker` y `GestureRecognizer` y en
`hands_updated` llama a `recognizer.update(hands, hands[0].t)`.

## Pruebas

- `-- mfmanos` recorre el sistema sin cámara, con manos sintéticas con la
  geometría de MediaPipe:
  - filtro One Euro: temblor frente a retardo;
  - clasificación de gestos;
  - histéresis y antirrebote;
  - cursor sin saltos;
  - zoom con dos manos y su sensibilidad;
  - fases del pellizco;
  - agarre con dos puños: traslación, profundidad, volante y fin del agarre;
  - precisión adaptativa;
  - controlador sobre el Laboratorio real: giro, pan, zoom, palma, deslizador y
    botón;
  - canal UDP con token;
  - autoprueba del proceso real (`mf_hands.py --selftest`: carga el modelo, mide
    la inferencia y envía una mano sintética por UDP).
- Diagnóstico manual del proceso: `python tools/handtracking/mf_hands.py --selftest --token X`.

## Privacidad y seguridad

- La cámara solo se abre mientras el seguimiento está activo. El proceso termina
  al desactivarlo o si MechaForge se cierra: vigila el PID del proceso padre.
- No se guarda ni se envía ninguna imagen, solo coordenadas, y solo a 127.0.0.1
  con token.
- La API de OpenClaw **no** puede activar la cámara.
