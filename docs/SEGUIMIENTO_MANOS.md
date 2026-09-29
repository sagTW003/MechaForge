# Seguimiento de manos en el Laboratorio matemático

Permite manejar el Laboratorio con las manos delante de la webcam: apuntar,
girar gráficas, arrastrar deslizadores, pulsar botones, hacer zoom con las dos
manos, agarrar la escena en 3D con los dos puños y pausar con la palma abierta.

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
| HandTracker | `project/handtracking/HandTracker.gd` | Lanza y cierra el proceso y escucha solo en 127.0.0.1, validando el token. Sigue a cada mano entre paquetes para que conserve su etiqueta (derecha o izquierda). Pasa cada coordenada por un filtro One Euro, publica `hands` y mide los fps y la latencia. |
| GestureRecognizer | `project/handtracking/GestureRecognizer.gd` | Máquina de estados por mano: apuntar, pellizco, puño, palma y reposo. Reconstruye la posición 3D de cada mano, aplica histéresis, antirrebote y el bloqueo del modo puño, gestiona la zona de interacción, el zoom y el agarre 3D. |
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
| ✊✊ **Dos puños** | Cerrar las dos manos (el pulgar da igual) | Agarra la escena en 3D, como un objeto sujeto con las dos manos. |
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

**Dos puños (agarre 3D):** al cerrar las dos manos se agarra la escena, que se
mueve como un objeto sujeto con ellas. El programa reconstruye la posición de cada
puño en el espacio real (en metros, ver abajo), así los tres ejes responden igual:
- **izquierda/derecha y arriba/abajo**: la escena se desplaza con las manos;
- **profundidad**: empujar los puños hacia la pantalla aleja la escena; tirar de
  ellos hacia uno la acerca. El centro de giro sigue en el objeto;
- **girar**: adelantar una mano y retrasar la otra gira la escena sobre la
  vertical, lo mismo que giran las manos (zona muerta de 5°);
- **inclinar**: doblar las dos muñecas hacia delante o hacia atrás inclina la
  escena (zona muerta de 8°).

Por defecto, 45 cm de recorrido de las manos cruzan el ancho de la vista. La
sensibilidad de cada parte se ajusta en el panel, y girar e inclinar se pueden
desactivar. Mover los puños de lado como un volante ya no gira: la cámara del
Laboratorio no tiene alabeo, y ese giro no corresponde a ningún movimiento real
del objeto.

Un puño solo no hace nada. El agarre termina al abrir una de las manos.

**Modo puño:** mientras una mano está en puño, sus pellizcos no cuentan. Así, al
cerrar o abrir el puño, o durante el agarre, el pulgar sobre el índice no gira la
escena ni pulsa nada. El bloqueo dura hasta que esa mano se abre: al apuntar, al
mostrar la palma o tras 0,3 s sin cerrarla. Mientras dura, el medidor del
pellizco indica «🔒 modo puño: abre la mano para pellizcar». Durante el agarre,
un pellizco accidental tampoco lo interrumpe ni activa el zoom.

**Reconstrucción 3D de las manos:** MediaPipe da la mano en metros pero centrada en
sí misma, sin la distancia a la cámara. La distancia se estima comparando los
huesos de la palma en la imagen (en píxeles) con los mismos huesos en metros,
proyectados en el plano de la imagen, lo que no depende de cómo esté girada la
mano. Con esa distancia y la posición en la imagen se obtienen x e y en metros
(cámara estenopeica con el campo de visión del panel, 62° por defecto). Por eso
10 cm de movimiento miden 10 cm con la mano a 65 cm o a 1 m. Las huesos de la
palma no cambian al cerrar la mano, así que sirve igual con el puño.

**Pellizco con la mano lejos:** con la mano pequeña en la imagen, los puntos de
MediaPipe son menos precisos y las puntas del pulgar y del índice no llegan a
juntarse del todo: los dedos juntos pueden leerse a 3–4 cm. Tres correcciones:
- **Compensación por distancia**: los umbrales crecen según el tamaño aparente de
  la mano. Por defecto se suman unos 12 px de imprecisión: a 1,5 m el pellizco se
  activa a ~4,9 cm en vez de 3 cm. Cerca no cambia nada. El medidor muestra la
  distancia de la mano y el umbral extra. Se ajusta en el panel con
  «Compensación con la mano lejos».
- **La coordenada de profundidad pesa menos** en la distancia pulgar–índice con la
  mano lejos, porque es la menos fiable.
- **Etiqueta estable**: con la mano lejos MediaPipe confunde a veces la derecha con
  la izquierda. Antes eso cortaba el pellizco, que pasaba a otra mano; ahora cada
  mano conserva su etiqueta mientras se la sigue, y solo cambia si MediaPipe
  insiste 8 paquetes seguidos.

Si aun así cuesta, activa **«Cámara en 1280×720»** en el panel: los puntos de una
mano lejana salen más precisos, aunque muchas cámaras bajan a 30 fps.

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
- **Zona de interacción**: un rectángulo de la imagen de la cámara, centrado y a
  la altura del pecho, se estira a toda la pantalla. No hace falta levantar el
  brazo («brazo de gorila»). Ahora es más amplia, 80 % × 67 % de la imagen (antes
  60 % × 50 %), para tener más espacio para maniobrar. Quien tuviera guardado el
  tamaño anterior pasa al nuevo automáticamente. Su tamaño y altura se ajustan en
  el panel.
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

Ordenado por secciones y con barra de desplazamiento:
- Mano principal.
- **Zona y cámara**: tamaño y altura de la zona de interacción, campo de visión de
  la webcam y cámara en 1280×720.
- **Pellizco**: umbrales, compensación con la mano lejos, sensibilidad de giro,
  ajuste fino, precisión adaptativa y sensibilidad del zoom.
- **Dos puños**: desplazamiento, profundidad, giro e inclinación (×), y casillas
  para girar e inclinar.
- **Filtro y pantalla**: suavizado (corte mínimo del One Euro), reactividad (β),
  esqueleto y puntero del ratón.

El HUD (abajo a la derecha) muestra:
- el minimapa, ahora más grande (320 × 240): la imagen de la cámara reducida a
  esqueleto, la zona de interacción y el gesto de cada mano;
- fps, latencia e inferencia;
- con algún puño a la vista, la **vista 3D de los puños**: el espacio delante de
  la webcam en perspectiva, desde «tú» hasta «pantalla». Muestra cada mano con su
  distancia a la cámara y su sombra en el suelo y, durante el agarre, los ejes x,
  y, z y lo desplazado (cm) y girado (°) desde que empezó.

El punto rojo indica que **la cámara está activa**.

La configuración se guarda en `%APPDATA%\Godot\app_userdata\MechaForge\mechaforge_hands.json`:
- `python`: ruta del intérprete si no es `python`;
- `camera`: -1 prueba de 0 a 3;
- `port`, `width`, `height`, `fps` (1280×720 si se activa en el panel);
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
| `grab_started` / `grab_moved` / `grab_ended` | `onGrabStart/Move/End` | `grab_moved(delta: Vector3, rot: Vector3)`. delta: metros, marco del usuario (x derecha, y arriba, z hacia la pantalla). rot, en rad: x inclinación de las muñecas, y giro horizontal (mano derecha hacia la pantalla > 0), z «volante» (mano derecha abajo > 0) |
| `grab_total()` | — | desplazamiento y giro acumulados desde el inicio del agarre (función) |
| `hand_p3(hand)` | — | posición 3D de una mano en metros desde la webcam (función) |
| `pinch_phase(hand)` | — | «lejos», «acercando», «cerrando», «activo», «soltando» o «bloqueado» (modo puño) (función, no señal) |
| `fist_locked(hand)`, `on_cm(hand)`, `off_cm(hand)` | — | bloqueo del modo puño y umbrales del pellizco con la compensación por distancia (funciones) |
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
  - reconstrucción 3D de la mano (cerca, lejos y girada) e inclinación de la muñeca;
  - pellizco con la mano lejos: compensación, sin falsos pellizcos y con ruido;
  - etiqueta estable aunque MediaPipe confunda derecha e izquierda;
  - modo puño: bloqueo del pellizco tras un puño y durante el agarre;
  - agarre 3D con puños simulados en el espacio (cámara estenopeica): x, y, z,
    diagonal, misma medida a otra distancia, giro, inclinación y fin del agarre;
  - precisión adaptativa;
  - controlador sobre el Laboratorio real: giro, pan, zoom, palma, agarre 3D
    (desplazar, subir, empujar/tirar, girar, inclinar), deslizador y botón;
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
