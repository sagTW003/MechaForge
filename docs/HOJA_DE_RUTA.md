# Hoja de ruta — MechaForge

Entrega por fases. Cada fase se valida antes de pasar a la siguiente.

## ✅ Fase 1 — Base (completada)
- [x] Proyecto Godot 4.7.2 (.NET), renderer Forward+ / Vulkan.
- [x] Cadena de herramientas C# verificada (.NET 8 + módulo `MassProperties`).
- [x] Entorno 3D: cielo físico, sol con sombras suaves, SDFGI, SSAO/SSIL, SSR,
      glow, niebla volumétrica, tonemapping ACES.
- [x] Suelo con rejilla CAD (shader) y ejes.
- [x] Cámara orbital (orbitar / pan / zoom / enfocar).
- [x] Perfiles gráficos automáticos (Bajo/Medio/Alto/Ultra) por GPU + escalado
      dinámico de resolución para FPS estables.
- [x] Biblioteca de piezas **definida por datos** (JSON), categoría estructural.
- [x] Colocación con snapping a rejilla configurable (mm), rotación, selección,
      duplicar, eliminar, **deshacer/rehacer**.
- [x] Panel de propiedades: material editable, dimensiones, volumen, densidad,
      **masa calculada**, posición.
- [x] Guardar/cargar proyectos en JSON (`.mforge`).
- [x] Interfaz en español, tema oscuro, atajos documentados.
- [x] Verificado: 101.8 FPS promedio con 200 piezas en perfil Ultra (RTX 5060).

## ✅ Fase 2 — Física (completada)
- [x] Cuerpos rígidos (Jolt) para las piezas; modo edición ↔ simulación con reinicio.
- [x] Uniones: **fija**, **bisagra** (con límites y motor), **deslizadera** (con
      límites) y **rótula**, creadas con el modo "Conectar".
- [x] Motores de bisagra con **curva torque–velocidad** de motor DC (HingeJoint3D).
- [x] Engranajes **acoplados cinemáticamente** (relación de transmisión).
- [x] Gravedad, fricción por material, colisiones, **centro de masa visible**.
- [x] Telemetría en vivo (posición, velocidad, velocidad angular, masa, COM).
- [x] Serialización de uniones (formato v2).
- [x] Pruebas de física automatizadas (5/5 OK): gravedad, reinicio, unión fija,
      motor y engranaje.
- [ ] Pendiente para 2.1: correas/poleas, amortiguación/rigidez ajustables por
      unión, y "anclaje al mundo" para bancos de prueba fijos.

## ✅ Fase 3 — Electrónica y control (núcleo completado)
- [x] **Solver eléctrico en C#** (Análisis Nodal Modificado, Ohm/Kirchhoff):
      tensiones de nodo, corriente, potencia y **autonomía de batería**.
- [x] **Controladores PID en C#** (anti-windup), configurables por unión
      (modo posición o velocidad, Kp/Ki/Kd, consigna).
- [x] Panel de **batería** (voltaje/capacidad) y **consumo** en vivo.
- [x] **Osciloscopio/gráfica en vivo** (consigna vs medida) y **exportar CSV**.
- [x] Biblioteca de **componentes electrónicos** (batería, MCU, driver, LED,
      motor DC, servo, actuador lineal, sensores).
- [x] Interop C#↔GDScript vía autoload `Electronics` (servicio).
- [x] Pruebas automatizadas (8/8): Ohm, serie, paralelo, autonomía, PID; y en
      simulación real: control PID de posición + consumo.
## ✅ Fase 3.1 — Cableado y microcontrolador (completada)
- [x] Componentes electrónicos con **terminales** (alimentación/señal/tierra) y
      propiedades eléctricas (batería: V/mAh; cargas: resistencia).
- [x] **Cableado visual** (modo Cablear): unir terminales con cables por color.
- [x] Net-list (union-find) → **análisis de circuito** con el solver C#
      (corriente, potencia, autonomía) en el panel "Circuito eléctrico".
- [x] **Microcontrolador programable por script**: editor con variables y
      funciones (sin, cos, abs, t, x…); genera la consigna de un control PID.
- [x] Serialización v3 (cables + batería). Pruebas: 14/14 electrónica.
- [ ] Opcional futuro: microcontrolador por **bloques visuales** (además del
      script) y wiring de señal que enlace sensores/actuadores automáticamente.

## ✅ Fase 4 — Integración OpenClaw (completada)
- [x] Puente `ai_bridge/OpenClawBridge.gd` al gateway local (endpoint compatible
      con OpenAI, `127.0.0.1:18789`), **autoconfigurado** leyendo el token de
      `~/.openclaw/openclaw.json` (guardado en `user://`, nunca en el código).
- [x] **Panel de chat** "OpenClaw (IA)" con estado de conexión, selector de
      **agente**, historial y envío de peticiones/preguntas.
- [x] El estado real de la escena se envía como contexto (diagnóstico fundado).
- [x] Protocolo de **acciones JSON** (`add_part`, `connect`, `set_property`,
      `remove`) parseado por `AiActions`; las propuestas se muestran como
      **vista previa "fantasma"** con **Aplicar/Descartar** (reversible con deshacer).
- [x] Conexión **solo local**; si OpenClaw no responde, la app funciona completa
      y muestra el estado.
- [x] Verificado en vivo: OpenClaw devolvió una acción `add_part` parseada por la
      app. Pruebas del parser: 16/16 base.

## ✅ Fase 5 — Análisis avanzado (completada)
- [x] **Mapa de esfuerzos** por carga (color verde→rojo) y **análisis de
      estabilidad/vuelco** (centro de masa vs base de apoyo).
- [x] **Plantillas**: Torre, Brazo robótico 3 GDL, Grúa, Puente, Pinza.
- [x] **Importación de modelos 3D**: GLTF/GLB (GLTFDocument), OBJ y STL
      (parsers propios) como piezas personalizadas, con autoescala.
- [x] **Exportar BOM** (lista de materiales) a CSV con cantidades y masas.
- [x] Barra de herramientas desplazable; FPS en la barra inferior.
- [x] Pruebas: BOM, importador OBJ y mapa de esfuerzos (19/19 base).
- [ ] Opcional futuro: rotura de piezas al superar el límite en simulación;
      persistencia de mallas importadas al guardar el proyecto.

## ✅ Refactor gráfico / construcción / física (plan externo, completado)
Plan de mejora en tres objetivos (fotorrealismo, maniobrabilidad, física):
- [x] **G1 Gráficos**: materiales nuevos (cobre, estaño, baquelita/PCB, fibra de
      carbono, acrílico), Depth of Field, bloom para LEDs.
- [x] **G+ Iluminación / HDRI**: `rendering/WorkEnvironment.gd` con entornos
      **Estudio** (HDRI procedural de softboxes), **Taller** (nave con ventanales y
      tubos fluorescentes) y **Exterior** (cielo físico, **ciclo día/noche**); carga
      de **HDRI propios** (.hdr/.exr/.png en `user://hdri`). Sombras PCSS suaves.
- [x] **G+ Texturas PBR procedurales** (`rendering/ProceduralTextures.gd`): albedo,
      rugosidad y normales por material (aluminio cepillado, anodizado granallado,
      acero laminado, cobre oxidado, PCB con pistas y vías, fibra de carbono en
      sarga 2x2 con laca, madera, hormigón...), mapeo triplanar a escala real,
      generadas en hilos de trabajo.
- [x] **G+ Mallas realistas** (`rendering/MeshFactory.gd`): perfiles 2020/4040 con
      **ranuras en T**, cajas **achaflanadas**, **tubo hueco**, **engranajes con
      dientes**, placas con **orificios M5** cada 20 mm, PCB con chip QFP, tira de
      pines y puntos de soldadura. Suelo con rejilla de grosor constante en píxeles.
- [x] **G+ Post-procesado**: antialiasing seleccionable **TAA+MSAA / SMAA / FXAA**,
      bloom, DOF con **autoenfoque** en el punto de interés, exposición.
- [x] **M1 Maniobrabilidad**: **gizmo 3D** de 3 ejes (mover/rotar, `W`/`E`),
      rotación en X/Y/Z por teclado (`R`, `Mayús+R`, `Alt+R`) con pasos **15/45/90°**
      (`1`/`2`/`3`); **encaje inteligente** (`core/SnapPoints.gd`) a orificios, ejes,
      extremos y ranuras en T con indicador (anillo y fantasma verdes).
- [x] **M1 Cableado**: **glow** de terminales por cercanía de la punta del cable y
      compatibilidad; **cable provisional** que sigue al cursor; color por función
      (VCC/GND/señal) o elegido.
- [x] **M2 Física de cables** (`electronics/CableSim.gd`): cuerda Verlet con
      gravedad (catenaria), longitud con holgura y **colisión** con piezas y suelo.
- [x] **M3 Soldadura** (`electronics/SolderingTool.gd`, `rendering/solder.gdshader`):
      cautín animado con punto de contacto exacto, estaño **sólido → líquido
      brillante → solidificado** en menisco, humo de fundente.
- [x] **F1 Motor↔circuito**, **F2 Steppers/Servos**, **F3 Engranajes Z1/Z2**.
- [x] **F2+**: stepper con **saltos discretos reales** (1.8°/microstep); servo
      limitado a su velocidad **s/60°** y detección de **bloqueo (stall)**.
- [x] **F3+ Engranajes dinámicos**: restricción por impulsos entre ambos cuerpos
      (la carga se refleja al motor, τ_a = r·τ_b), **huelgo** configurable,
      **rendimiento** (fricción) y corrección de fase sin desincronización.
- [x] Motor DC con modelo τ = τ_bloqueo·(u − ω/ω0) (incluye frenado dinámico).
- [x] **Correcciones**: eje de giro de las bisagras (era el X local, Jolt usa el Z
      local) y sentido del motor; cuerpos "fantasma" al reiniciar en el mismo frame.
- [x] Pruebas `mfrefactor` (39/39). Benchmark: **119 FPS** promedio (1 % bajo 111)
      con 200 piezas en Ultra (RTX 5060).

## ✅ Detalles finales del documento del proyecto (completados)
- [x] **API de herramientas para OpenClaw** (`ai_bridge/ToolServer.gd` +
      `SimulatorApi.gd`): JSON-RPC 2.0 sobre HTTP en `127.0.0.1:18790` con token;
      `get_scene_state`, `add_part`, `connect_parts`, `set_property`, `remove_part`,
      `write_controller_script`, `run_simulation`, `stop_simulation`,
      `get_telemetry`, `analyze_design`. Los cambios llegan como **vista previa con
      confirmación**. *Skill* lista en `openclaw_skill/mechaforge/`.
- [x] **Microcontrolador por bloques visuales** (tipo Scratch, `ui/BlockEditor.gd`)
      además del script; varias salidas `m1..mN` para mover varios actuadores.
- [x] **API de sensores** (`control/Sensors.gd`): ultrasonido, LiDAR 2D, encoder,
      IMU, final de carrera, sensor de fuerza y sensor de línea IR.
- [x] **Pausa, avance cuadro a cuadro y cámara lenta** (1×, 0.5×, 0.25×, 0.1×).
- [x] **Temperatura estimada del motor** (modelo térmico I²R de primer orden).
- [x] **Autoguardado** cada 2 min con **Recuperar**; **copiar/pegar**; **simetría**.
- [x] **Anclaje al mundo** por pieza (bancos de prueba, pistas) — pendiente de 2.1.
- [x] **Plantillas**: brazo robótico **4 GDL** con PID y **carro seguidor de línea**
      funcional (pista de cinta, dos sensores IR, control diferencial).
- [x] Piezas nuevas: rueda Ø65, bola loca de teflón, cinta de pista, chasis,
      final de carrera, FSR, LiDAR, sensor de línea; material PTFE; forma esfera.
- [x] **Persistencia de modelos importados** (se re-importan al abrir el proyecto).
- [x] Correcciones: control de velocidad (prealimentación + PID, sin oscilación),
      marcadores de uniones mal orientados, búfer HTTP.
- [x] Pruebas `mffinal` (37/37).

## ✅ Proyectos de ejemplo e instalación de la skill
- [x] **9 proyectos de ejemplo** en `project/templates/*.mforge` (menú «Ejemplos»):
      brazo 4 GDL, seguidor de línea, evita-obstáculos, reductora 16:60, banco PID,
      circuito LED, grúa, puente con carga y péndulo doble. Generador reproducible
      (`-- mfgen`) y prueba que abre y simula cada uno (`-- mfejemplos`, 29/29).
- [x] Los proyectos guardan programa del microcontrolador, vista y entorno.
- [x] Skill `mechaforge` instalada en OpenClaw (`openclaw skills info mechaforge` → Ready).
- [x] Correcciones de física halladas con los ejemplos: inercia del conjunto rígido
      en engranajes, prealimentación en control de posición, ángulo de unión exacto
      (sin deriva) y eje de la unión solidario al cuerpo (vehículos que giran).

## ✅ Fase 6 — Pulido y empaquetado
- [x] Rendimiento verificado: **119 FPS** promedio (1 % bajo 111) con 200 piezas en
      Ultra (RTX 5060); mallas compartidas, texturas en hilos, física de cables con
      filtrado de obstáculos.
- [x] **Carpeta portable** para Windows (`tools/empaquetar.ps1 -Zip` →
      `dist/MechaForge_portable` + `.zip`): runtime .NET de Godot incluido, proyecto
      precompilado, lanzador sin consola (`MechaForge.vbs`). Verificada ejecutando
      las pruebas dentro de la copia portable.
- [x] **Ejecutable exportado** (`tools/empaquetar.ps1 -Exe` → `dist/MechaForge_exe`)
      con las plantillas oficiales .NET 4.7.2 (SHA-512 verificado), icono propio y
      piezas/ejemplos incluidos; verificado ejecutando mftest, mfejemplos y mfphys
      con el propio `.exe`.
- [ ] Opcional futuro: rotura de piezas en simulación; correas/poleas.
