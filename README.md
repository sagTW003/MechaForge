# MechaForge

**Simulador virtual de construcción mecatrónica e ingeniería** — un "sandbox de
ingeniería" para diseñar, ensamblar, programar y probar mecanismos, robots,
vehículos, grúas, estructuras, transmisiones y sistemas de control, con física
realista y gráficos de alta calidad.

> Estado: **todas las fases (1–6) completadas**: construcción, física, electrónica y
> control (script y bloques, sensores), integración con OpenClaw (chat + API de
> herramientas), análisis, refactor gráfico (HDRI, PBR procedural, ranuras en T),
> gizmo 3D, encaje inteligente, cables con física, soldadura, engranajes dinámicos,
> plantillas (brazo 4 GDL, seguidor de línea) y versión portable.
> Ver [docs/HOJA_DE_RUTA.md](docs/HOJA_DE_RUTA.md).

![Refactor](docs/demo_refactor.png)
*Estudio (HDRI procedural): bastidor de perfiles 2020 con ranura en T sobre placa perforada, tren de engranajes Z20/Z40, PCB y gizmo 3D.*

![Cables y soldadura](docs/demo_cables_soldadura.png)
*Taller: cables con física (catenaria, sin atravesar piezas), conectores Dupont, PCB con chip y tira de pines, fibra de carbono.*

![Demostración Fase 1](docs/demo_fase1.png)
*Fase 1 — construcción.*

![Demostración Fase 2](docs/demo_fase2.png)
*Fase 2 — simulación física: brazo motorizado, centro de masa (esfera rosa) y telemetría.*

![Demostración Fase 3](docs/demo_fase3.png)
*Fase 3 — control PID de posición con gráfica en vivo y panel de consumo/autonomía.*

![Cableado](docs/demo_cableado.png)
*Fase 3.1 — cableado visual (batería + resistencia + LED) y análisis de circuito.*

![Microcontrolador](docs/demo_mcu.png)
*Fase 3.1 — microcontrolador programable: el script `sin(t)` genera la consigna que sigue el PID.*

---

## Requisitos

- **Windows 10/11** (probado en Windows 11 Pro).
- **GPU con Vulkan** (Forward+). Probado en NVIDIA GeForce RTX 5060 (8 GB).
- **Godot 4.7.2 — edición .NET/Mono** (incluida en `tools/godot/`).
- **.NET SDK 8** (para los módulos en C#). Verifica con `dotnet --version`.

El proyecto se ejecuta también en GPUs más modestas: los **perfiles gráficos
automáticos** (Bajo/Medio/Alto/Ultra) y el **escalado dinámico de resolución**
ajustan la calidad para mantener los FPS estables.

## Cómo ejecutar

### Opción A — Con el editor de Godot (recomendado para desarrollo)

1. Abre el editor .NET de Godot incluido:
   ```
   tools\godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe
   ```
2. Importa el proyecto: pulsa **Importar** y selecciona
   `project\project.godot`.
3. Pulsa **F5** (Ejecutar) o el botón ▶.

### Opción B — Directo por línea de comandos

```bat
tools\godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe --path project
```

### Modos de verificación (para desarrollo)

- **Benchmark de FPS con 200 piezas** (mide y cierra solo):
  ```bat
  ...\Godot_...mono_win64.exe --path project -- mfbench
  ```
- **Captura de demostración** (renderiza un ensamblaje y guarda un PNG):
  ```bat
  ...\Godot_...mono_win64.exe --path project -- mfshot docs\demo_fase1.png
  ```

## Controles

| Acción | Control |
|---|---|
| Colocar pieza / seleccionar | Clic izquierdo |
| Mover pieza colocada | Arrastrar (X/Z) |
| **Encajar sobre otra pieza** | Arrastrar encima (opción `Encajar`) |
| Mover en altura | Mantener `Z` + arrastrar |
| Ajuste fino por rejilla | Flechas · `Re/Av Pág` (altura) |
| Cancelar / deseleccionar | Clic derecho o `Esc` |
| Orbitar cámara | Botón central del ratón |
| Desplazar (pan) | `Mayús` + botón central |
| Zoom | Rueda del ratón |
| Centrar cámara | `F` |
| Rotar pieza | `R` |
| Eliminar pieza | `Supr` |
| Duplicar | `Ctrl+D` |
| Deshacer / Rehacer | `Ctrl+Z` / `Ctrl+Y` |
| Guardar / Abrir | `Ctrl+S` / `Ctrl+O` |
| Snapping a rejilla | `G` |
| **Simular / detener** | `Espacio` |
| **Conectar dos piezas** | Botón `🔗 Conectar` |
| **Reiniciar simulación** | Botón `⟲ Reiniciar` |
| Ayuda | `H` o `F1` |

Lista completa en [docs/ATAJOS.md](docs/ATAJOS.md).

### Física (Fase 2)

Pulsa **▶ Simular** (o `Espacio`) para activar la física (Jolt, 120 Hz). Las
piezas se vuelven cuerpos rígidos con su masa real, gravedad, fricción y
colisiones. Con **🔗 Conectar** unes dos piezas mediante:

- **Fija** — soldadura rígida.
- **Bisagra** — giro sobre un eje, con límites opcionales y **motor** (curva
  torque–velocidad de motor DC: velocidad objetivo, torque de arranque, velocidad
  sin carga).
- **Deslizadera** — desplazamiento lineal sobre un eje, con límites.
- **Rótula** — giro libre en los tres ejes.
- **Engranaje** — acoplamiento cinemático por relación de transmisión.

Durante la simulación, al seleccionar una pieza se muestra su **telemetría en
vivo** y el **centro de masa** del conjunto (esfera rosa). **⟲ Reiniciar**
devuelve todo al estado inicial exacto.

### Verificación de física
```bat
...\Godot_...mono_win64.exe --headless --path project -- mfphys
```
Ejecuta las pruebas de física (gravedad, reinicio, unión fija, motor, engranaje).

### Electrónica y control (Fase 3)

Al crear una **bisagra con motor**, en el diálogo puedes activar un **control PID**
(posición o velocidad) con su consigna y ganancias Kp/Ki/Kd. Durante la simulación
aparece el panel **Electrónica y control** (abajo a la izquierda) con:

- **Batería** editable (voltaje y capacidad en mAh).
- **Consumo** calculado por el solver eléctrico en C# (corriente, potencia) y la
  **autonomía** estimada.
- **Osciloscopio en vivo** (consigna vs medida) de la unión controlada elegida.
- **Exportar CSV** de la telemetría de control.

### Cableado y microcontrolador (Fase 3.1)

- **🔌 Cablear**: coloca componentes electrónicos (batería, LED, resistencia,
  motor…), entra en modo Cablear y une sus **terminales** (bolas de color) con
  cables. El panel **Circuito eléctrico** analiza el circuito (net-list resuelto
  con el solver en C#): corriente, potencia y autonomía.
- **Microcontrolador**: escribe un programa con variables y funciones
  (`amp = 40`, `output = sin(t) * amp`) que genera la **consigna** de un control
  PID durante la simulación. Variables disponibles: `t` (tiempo), `x` (medida), `dt`.

Pruebas de electrónica y control:
```bat
...\Godot_...mono_win64.exe --headless --path project -- mfelec
```

### Entorno, gráficos y construcción (refactor)

- Panel **Entorno y gráficos**: **Estudio** (softboxes, ideal para ver materiales),
  **Taller** o **Cochera (exterior)** (con **ciclo día/noche**). Puedes añadir tus
  propios **HDRI** (`.hdr`, `.exr`, `.png`) en `%APPDATA%\Godot\app_userdata\MechaForge\hdri`
  y pulsar *⟳ Buscar HDRI*. Antialiasing TAA+MSAA / SMAA / FXAA, bloom, DOF.
- **Gizmo 3D**: selecciona una pieza y arrastra sus flechas (mover) o anillos
  (rotar). `W`/`E` cambian el modo; `R`, `Mayús+R`, `Alt+R` giran en Y/X/Z con pasos
  `1`/`2`/`3` = 15°/45°/90°.
- **Encaje inteligente**: al acercar una pieza a otra se ajusta a orificios, ejes,
  extremos y ranuras en T (anillo verde).
- **Cableado**: los terminales brillan al acercar la punta; cable provisional con
  física; colores por función o personalizados. **🔥 Soldar** anima el cautín y el
  estaño fundiéndose y solidificándose.
- **Engranajes** de la biblioteca (*Transmisión*, Z16–Z60 módulo 1): al unir dos
  con 🔗 *Conectar* se rellenan sus dientes; configura **huelgo** y **rendimiento**.

Pruebas del refactor:
```bat
...\Godot_...mono_win64.exe --headless --path project -- mfrefactor
```

### Entorno «Cochera (exterior)»

Una cochera doméstica para probar las construcciones como en casa: nave de 7 × 7 m con
el portón abierto a la entrada de coches (HDRI real «Preller Drive»), banco de trabajo
con panel de herramientas, estantería con cajas, gabinete, neumáticos, lámparas
fluorescentes y una zona de pruebas con **rampa de 12°**, tope y conos. Paredes,
muebles, rampa y conos **tienen colisión**: los vehículos simulados chocan con ellos y
suben la rampa. La hora del día mueve el sol que entra por el portón (y de noche
encienden las lámparas). Texturas fotográficas CC0 (ver `project/assets/CREDITOS.md`).

![Cochera](docs/demo_cochera.png)
*Entorno «Cochera»: el robot evita-obstáculos en la zona de pruebas.*

![Cochera, portón](docs/demo_cochera_fondo.png)
*Portón abierto hacia la entrada de coches, rampa y conos.*

### Electrónica con texturas reales y protoboard MB-102

- Carcasas, motores, ruedas, pines y contactos usan **texturas fotográficas** (plástico
  texturado, metal cepillado y satinado, caucho) de ambientCG (CC0).
- La **protoboard** es una MB-102 de **830 puntos** con medidas reales (paso 2,54 mm,
  canal central de 7,62 mm, rieles de 50 puntos en grupos de 5, filas a–j y columnas
  numeradas). Los agujeros dibujados y los terminales de cableado salen de la misma
  tabla de posiciones, así que **cada terminal cae exactamente en su agujero**.

![Protoboard](docs/demo_protoboard.png)
*Modo cableado sobre la protoboard: cada marcador de terminal coincide con un agujero.*

### Seleccionar una unión

En el panel **Uniones** cada unión lleva un número que también aparece **flotando en
3D** junto a su anclaje. Haz clic en la fila (o en la esfera del marcador en 3D) para
**seleccionarla**: se resaltan el marcador y sus dos piezas (en cian) y se muestran sus
datos (piezas A/B, eje, anclaje, motor, control). 🎯 la encuadra con la cámara y
`Supr` o ✕ la borran.

![Uniones](docs/demo_uniones.png)
*Unión nº 4 seleccionada: piezas resaltadas y detalle en el panel.*

### Multímetro digital, integrados DIP y cortocircuitos

**Circuito vivo.** El circuito se resuelve continuamente (en edición y en simulación)
con un solver de **Análisis Nodal Modificado no lineal** (C#, Newton-Raphson con
limitación de la tensión de unión): los **LED son diodos reales** (≈1.85 V a 15 mA en
rojo), las baterías tienen resistencia interna, cada cable es un elemento con su
corriente y el **NE555** oscila en modo astable. Un LED sin resistencia se **quema**, una
resistencia que disipa de más humea y se abre.

**Multímetro (📟).** Pieza *Instrumentos de medida → Multímetro digital*: carcasa de
goma, **LCD de 7 segmentos dibujada por shader** (dígitos, punto decimal, «OL», «Err»,
«FUSE», iconos de batería, AC/DC y continuidad), **selector giratorio** (OFF, V⎓, V~,
A⎓, Ω, continuidad) y bornes 10 A / COM / VΩmA. Sus **sondas roja y negra** cuelgan de
cables de silicona con física de cuerda: arrástralas y su punta hace un **snap
magnético** al terminal más cercano (agujero de la protoboard, pata de un componente,
pin del Arduino) — **vertical (90°)** en agujeros y pines, **inclinada 45°** en patas y
bornes, en «V» si las dos están juntas.

| Modo | Qué mide | Regla |
|---|---|---|
| V⎓ / V~ | V(roja) − V(negra) (V~: valor eficaz de la componente alterna) | En paralelo, 10 MΩ: no altera el circuito |
| A⎓ | Corriente por el derivador (VΩmA: 1 Ω · fusible 400 mA; 10 A: 0.01 Ω · fusible 10 A) | En **serie**. En paralelo con la fuente **funde el fusible**: chispas, «FUSE» y hay que reemplazarlo |
| Ω | Resistencia equivalente entre puntas (inyecta 1 V por 10 kΩ) | Solo **desenergizado**; si hay una fuente conectada muestra «Err» |
| 🔊 | Continuidad | Pita (tono de 2.7 kHz) y enciende el LED si R < 50 Ω |

**Cortocircuito crítico.** Si una fuente queda con menos de 0.5 Ω de carga y más de
1 A, se activa el estado de **CORTOCIRCUITO CRÍTICO**: chispas 3D (partículas GPU),
humo del aislamiento, el cable se pone **al rojo** (shader de cuerpo negro según su
temperatura, modelo térmico I²R) y la **protección térmica desconecta la fuente**. Un
aviso rojo ofrece **⟲ Rearmar** tras corregir el cableado.

**Protoboard multipín.** Resistencias, LED e **integrados DIP** (NE555 DIP-8, Arduino
Nano DIP-30) se **insertan**: sus patas entran en los agujeros y quedan conectadas sin
cables. Un DIP solo encaja si **cruza el canal central** (una fila en a–e y la otra en
f–j) y todas sus patas caen en agujeros válidos; si no, se explica por qué. Al mover o
girar la protoboard, **todo lo insertado (y las sondas enganchadas) la sigue**; en
simulación forman un único cuerpo rígido. El Arduino Nano se alimenta por USB (5V y
3V3) y el programa del microcontrolador escribe sus salidas `d2`…`d13`.

![Multímetro](docs/demo_multimetro.png)
*Ejemplo «Multímetro en protoboard»: 1.847 V en el LED; sondas en «V» en agujeros vecinos.*

![LCD](docs/demo_multimetro_lcd.png)
*LCD de 7 segmentos por shader, selector en DCV y clavijas en COM y VΩmA.*

![DIP](docs/demo_dip.png)
*Arduino Nano (DIP-30) y NE555 (DIP-8) cruzando el canal central.*

![Cortocircuito](docs/demo_cortocircuito.png)
*Puente de riel + a riel −: cortocircuito crítico, humo, chispas y aviso de protección.*

![Fusible](docs/demo_fusible.png)
*Amperímetro en paralelo con la pila: fusible de 400 mA fundido («FUSE»).*

### Proyectos de ejemplo (menú «Ejemplos»)

Once proyectos completos, listos para pulsar ▶ Simular (se abren como proyecto sin
título; guárdalos con «Guardar como…»):

| Ejemplo | Qué muestra |
|---|---|
| Brazo robótico 4 GDL | 4 articulaciones con PID; trayectorias senoidales desde el microcontrolador (`m1…m4`) |
| Carro seguidor de línea | Dos sensores IR, pista de cinta y control diferencial de velocidad |
| Robot evita-obstáculos | Ultrasonido frontal en un recinto: gira al detectar una pared a < 25 cm |
| Reductora de engranajes 16:60 | Motor con inversión de giro, relación −16/60 y huelgo visibles |
| Banco de control PID | Brazo siguiendo una onda (programa por bloques) con encoder en el eje |
| Circuito LED en protoboard | Batería, resistencia de 470 Ω y LED **insertados** en la protoboard (LED = diodo real) |
| Grúa giratoria con contrapeso | Giro de la pluma por PID; estabilidad con el mapa de esfuerzos |
| Puente con carga | Viga con dos cargas sobre pilares anclados |
| Péndulo doble | Dinámica caótica con conservación de la energía |
| Multímetro en protoboard | Tensión en el LED y en la resistencia, continuidad, corriente en serie |
| Arduino Nano y NE555 (DIP) | Integrados que cruzan el canal; 555 astable y salidas `d2`/`d13` del programa |

Los ejemplos son archivos `.mforge` en `project/templates/`: **añadir un proyecto
al menú = copiar ahí un `.mforge`** (con `"nombre"` y `"descripcion"`). Se regeneran
con `-- mfgen` (`project/templates/GeneradorEjemplos.gd`). Los proyectos guardan
ahora también el programa del microcontrolador, la vista de cámara y el entorno.

![Evita-obstáculos](docs/demo_03_evita_obstaculos.png)
*Ejemplo «Robot evita-obstáculos»: sensor ultrasónico (`dist1`) y regla en el microcontrolador.*

![Reductora](docs/demo_04_reductora.png)
*Ejemplo «Reductora de engranajes 16:60».*

### Microcontrolador: bloques, sensores y varios actuadores

El panel **Microcontrolador** tiene dos pestañas: **Script** y **Bloques** (tipo
Scratch: *Fijar*, *Si/si no*, *Onda*, *Escalón*, *Seguir sensor*, *Limitar*,
*Motor n*, *Salida*; pulsa *Generar script desde bloques*). Los sensores de la
escena aparecen como variables: `dist1` (ultrasonido), `lidar1`, `enc1`,
`imu1_pitch`/`imu1_roll`, `fin1` (final de carrera), `fuerza1`, `linea1` (IR).
Además de `output`, las variables `m1`, `m2`… fijan la consigna de cada unión con
control, en orden. Plantilla de ejemplo: **Carro seguidor de línea**.

![Seguidor de línea](docs/demo_seguidor.png)
*Carro seguidor de línea: dos sensores IR, control diferencial de velocidad y el programa del microcontrolador.*

### Simulación: pausa, paso a paso y cámara lenta

Durante la simulación: `⏸`/`P` pausa, `⏭`/`.` avanza un paso físico (1/120 s) y el
selector de velocidad da cámara lenta (0.5×, 0.25×, 0.1×). El panel de electrónica
muestra también la **temperatura estimada de los motores**. Cada pieza puede
**anclarse al mundo** (casilla en Propiedades) para bancos de prueba o pistas.

### API para OpenClaw (herramientas)

Además del chat, MechaForge expone una **API local JSON-RPC** en
`http://127.0.0.1:18790` (token en `%APPDATA%\Godot\app_userdata\MechaForge\mechaforge_api.json`)
con las herramientas `get_scene_state`, `add_part`, `connect_parts`, `set_property`,
`remove_part`, `write_controller_script`, `run_simulation`, `stop_simulation`,
`get_telemetry`, `analyze_design`, `get_circuit_state` (fuentes, LED, cortocircuito,
piezas insertadas y lectura del multímetro) y `measure_voltage` (medida de solo
lectura entre dos terminales). Todo cambio llega como **vista previa** y lo
confirmas tú. La *skill* **mechaforge** está instalada en OpenClaw (`~/.openclaw/skills/mechaforge`,
copia de `openclaw_skill/mechaforge/`): pide a tu agente, con MechaForge abierto,
cosas como *«usa mechaforge para analizar el diseño»*.

### Autoguardado

Cada 2 minutos se guarda una copia en `autoguardado.mforge` si hay cambios; el botón
**Recuperar** la abre.

## Ejecutable para Windows

```bat
powershell -ExecutionPolicy Bypass -File tools\empaquetar.ps1 -Zip -Exe
```
Genera dos distribuciones en `dist\`:

- **`MechaForge_exe\`** (+ `MechaForge_windows.zip`): ejecutable exportado con las
  plantillas oficiales de Godot 4.7.2 .NET — `MechaForge.exe` (con su icono),
  `MechaForge.console.exe` (muestra el registro), `MechaForge.pck` y la carpeta de
  ensamblados .NET. Incluye las piezas y los proyectos de ejemplo.
- **`MechaForge_portable\`** (+ `.zip`): alternativa que ejecuta el proyecto con el
  runtime de Godot incluido (doble clic en `MechaForge.vbs`).

Ambas requieren el runtime de **.NET 8** y una GPU con Vulkan. El script verifica
cada copia ejecutando las pruebas dentro de ella.

## Pruebas

| Suite | Comando (`...\Godot_...mono_win64_console.exe --headless --path project -- <suite>`) |
|---|---|
| Base (Fase 1, IA, BOM, importación) | `mftest` |
| Física | `mfphys` |
| Electrónica y control | `mfelec` |
| Refactor gráfico/construcción/física | `mfrefactor` |
| Detalles finales (API, sensores, bloques, plantillas…) | `mffinal` |
| Proyectos de ejemplo (abre y simula cada uno) | `mfejemplos` |
| Protoboard, uniones, cochera y texturas | `mfentorno` |
| Multímetro, protoboard multipín (DIP) y cortocircuitos | `mfmulti` |

## Arquitectura

Modular por carpetas dentro de `project/`:

| Módulo | Responsabilidad |
|---|---|
| `core/` | Escena, piezas (definidas por datos), materiales, uniones, unidades SI, cálculo (C#) |
| `physics/` | Simulador Jolt: cuerpos rígidos, uniones, motores, engranajes, centro de masa |
| `electronics/` | Solver eléctrico, cableado, física de cables y soldadura |
| `control/` | PID (C#), sensores del microcontrolador |
| `rendering/` | Perfiles gráficos, entorno (HDRI/día-noche), texturas procedurales, mallas, shaders |
| `ui/` | Interfaz, cámara orbital, controlador principal |
| `ai_bridge/` | Puente con OpenClaw (chat) y API local de herramientas |
| `io/` | Serialización de proyectos (JSON) |

Detalle en [docs/ARQUITECTURA.md](docs/ARQUITECTURA.md).

### Piezas definidas por datos

Cada pieza es un objeto JSON en `project/parts/`. **Para añadir una pieza nueva,
crea o edita un `.json`** — no hace falta tocar código. Ejemplo en
`project/parts/estructural.json`.

## Integración con OpenClaw (IA personalizada) — *Fase 4*

MechaForge se conecta a tu **OpenClaw** local (gateway `127.0.0.1:18789`, endpoint
compatible con OpenAI) mediante el módulo desacoplado `ai_bridge`. El puente se
**autoconfigura** leyendo el token de tu `~/.openclaw/openclaw.json` y lo guarda
en `user://openclaw_config.json` (**nunca en el código ni en el repo**).

Botón **🤖 IA** → panel de chat "OpenClaw (IA)":
- **Estado de conexión** y selector de **agente** (cerebro, main, …).
- Escribe peticiones (*"arma una torre de 4 perfiles"*) o preguntas de
  diagnóstico; se envía el **estado real de la escena** como contexto.
- Las propuestas de la IA se muestran como **piezas fantasma** con
  **Aplicar / Descartar** (reversible con deshacer). Conexión **solo local**.
- Si OpenClaw no responde, la app funciona completa y lo indica.

![IA](docs/demo_ia.png)
*Fase 4 — chat con OpenClaw conectado (agente cerebro), con el estado de la escena como contexto.*

Detalles en [docs/INTEGRACION_OPENCLAW.md](docs/INTEGRACION_OPENCLAW.md).

## Formato de proyecto

Los proyectos se guardan como JSON legible con extensión `.mforge`
(ver `project/io/ProjectSerializer.gd`).

## Licencia

Proyecto personal. Godot Engine se distribuye bajo licencia MIT.
