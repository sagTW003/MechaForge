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

## ✅ Seguimiento de manos (Laboratorio)
- [x] `mf_hands.py`: webcam (hilo de captura con el último fotograma) + MediaPipe
      HandLandmarker en un proceso aparte → UDP 127.0.0.1 con token; autoprueba sin
      cámara; se cierra solo si MechaForge termina.
- [x] Tres capas en Godot: `HandTracker` (proceso, UDP, One Euro), `GestureRecognizer`
      (apuntar, pellizco, dos pellizcos, palma; histéresis, antirrebote, deriva del
      clic y al soltar, zona de interacción) y `VirtualLabController` (cursor, clics
      inyectados, ajuste fino de deslizadores, giro, pan, zoom, pausa y reinicio de
      vista; HUD con esqueleto y latencia; panel de ajustes).
- [x] Pruebas `mfmanos` con manos sintéticas y el proceso real de MediaPipe.
- [x] Agarre con dos puños en 3D real: posición de cada mano en metros (cámara
      estenopeica), desplazamiento en x, y, z, giro e inclinación; vista 3D de los
      puños en el HUD; modo puño que bloquea el pellizco.
- [x] Pellizco con la mano lejos: compensación por distancia y etiqueta estable de
      cada mano; zona de interacción y minimapa más grandes; opción 1280×720.
- [ ] Probarlo con la webcam real y ajustar los valores por defecto (compensación,
      zonas muertas, campo de visión).

## ✅ Laboratorio matemático 3D
- [x] Modo **∑ Laboratorio** dentro de MechaForge (la escena del simulador se conserva)
      con escenario holodeck, post-procesado completo y cámara amortiguada con vistas
      perspectiva / superior 2D / isométrica y encuadre de puntos críticos.
- [x] `MathExpr`: analizador propio (implícitos, |x|, constantes, i) con evaluación real
      y compleja, compilación a Expression nativa y **traducción a GLSL**.
- [x] EDP en C# (`FieldSim.cs`: onda FDTD con Mur, calor con α por celda, Schrödinger
      con Visscher y absorción en bordes) → textura RGBA float → malla deformada en GPU.
- [x] 17 módulos: onda, calor, Schrödinger · raíces, sistemas, sistemas no lineales,
      optimización, interpolación y ajuste, interpolación 1D, integración doble,
      integración y derivación 1D, EDP numérica ·
      coloreado de dominio, mapeos conformes, fractales · campos vectoriales y teoremas
      de Gauss/Stokes.
- [x] Métodos numéricos ampliados:
  - raíces: 15 métodos con comparación;
  - sistemas lineales: SOR, Richardson, descenso, gradiente conjugado, eliminación
    geométrica, LU, Cholesky, QR y Cramer;
  - sistemas no lineales: 7 métodos y cuencas de Newton en GPU;
  - interpolación 1D: 13 métodos, nodos de Chebyshev y constante de Lebesgue;
  - interpolación 3D: B-spline, Bézier, IDW, RBF y Delaunay.
- [x] Integración y derivación 1D (módulo `calculo`): 18 cuadraturas, entre ellas
      Gauss–Kronrod adaptativa, tanh-sinh, Monte Carlo y Gauss–Laguerre/Hermite para
      intervalos infinitos, y 14 derivadas de 1.º y 2.º orden, entre ellas Richardson,
      paso complejo, diferenciación automática y derivada simbólica. Integración doble
      con Gauss–Legendre, Monte Carlo y Halton. Solvers en `mathlab/solvers/Quadrature.gd`
      y `NumDiff.gd`.
- [x] Fórmulas como en papel: funciones sin paréntesis, nombres en español,
      superíndices, √, palabras pegadas, coma decimal y cierre de paréntesis. Vista
      previa en notación matemática, sugerencias y teclado de símbolos.
- [x] Reproducible en cualquier PC: `tools\preparar_godot.ps1` descarga Godot 4.7.2 .NET
      oficial (SHA-512) y sus plantillas; NuGet solo desde nuget.org; un clon limpio
      compila y pasa todas las pruebas. Ejecutable autónomo con respaldo a D3D12/OpenGL
      y lanzador de modo compatible; barra superior en varias filas.
- [x] Herramienta Perturbar, tooltip 3D, planos de corte X/Y/Z.
- [x] Pruebas `mflabtest` que comprueban la matemática de cada módulo.
- [x] API `lab_*` para OpenClaw y skill **mechaforge-laboratorio** (instalada con
      permiso). La API local sigue viva mientras el laboratorio está abierto.

## ✅ Integración y derivación numéricas en 2D
- [x] El módulo `integracion` pasa a **Integración y derivación (2D)** (mismo id para
      la API), con dos modos.
- [x] **Región** a ≤ x ≤ b, c(x) ≤ y ≤ d(x) con límites que pueden depender de x
      (triángulo, disco, entre curvas). Se lleva al cuadrado unidad con su jacobiano,
      así todos los métodos sirven para cualquier región.
- [x] **19 métodos de integración**: rectángulo, punto medio, trapecio, Simpson 1/3
      y 3/8, Boole, Romberg iterada, Gauss–Legendre y Gauss–Lobatto p × p,
      Clenshaw–Curtis, cubatura de 7 puntos de grado 5, Gauss–Kronrod, Simpson y
      tanh-sinh iteradas, Genz–Malik adaptativa, Monte Carlo, estratificado, Halton y
      retícula de Fibonacci. Prismas por celda o subregión, nodos de evaluación y error
      frente a evaluaciones.
- [x] **Derivación parcial**: ∂f/∂x, ∂f/∂y, ∂²f/∂x², ∂²f/∂y², ∂²f/∂x∂y, laplaciano,
      |∇f| y derivada direccional con 11 métodos (diferencias de 2 a 7 puntos,
      Richardson, paso complejo, automática, simbólica, 9 puntos y mínimos cuadrados).
      Plano tangente, ∇f, cortes por P, hessiana, ruido y error frente a h.
- [x] 27 pruebas nuevas en `mflabtest` (órdenes observados, regiones curvas,
      singularidad, pesos de Genz–Malik, órdenes de las derivadas, ruido).
- [x] **Verificación de todos los métodos** (1D y 2D): barridos con todos los ejemplos
      frente al valor exacto, comprobado por caminos independientes (diferenciación
      automática frente a simbólica, NumPy para Gauss–Hermite). Corregidos la retícula
      de Fibonacci (un punto caía en la esquina singular) y las adaptativas iteradas
      (si la tolerancia no cabe en el presupuesto se relaja y se avisa en lugar de no dar
      valor). Quedan como pruebas permanentes en `mflabtest` (~1000 casos).

## ✅ Elección de la cámara del seguimiento de manos
- [x] Desplegable **Cámara** en el panel «✋ Seguimiento de manos», con «Automática»
      y **↻ Buscar cámaras**. `handtracking/CameraList.cs` enumera DirectShow (mismo
      orden que OpenCV) sin encender ninguna cámara.
- [x] La cámara se guarda con su nombre y se busca por él al arrancar; si no está
      conectada se usa la automática y el panel lo avisa. `mf_hands.py --camera-name`.
- [x] 10 pruebas nuevas en `mfmanos` (61 sin ventana y 62 con ventana).

## ✅ Imágenes y PDF en el chat de OpenClaw
- [x] **Adjuntos** en el panel de IA (📎, arrastrar a la ventana o Ctrl+V; hasta 6
      por mensaje). `ai_bridge/AiAttachments.gd` los prepara para cualquier agente:
      imágenes como `image_url` (reducidas a 1600 px), el texto de los PDF marcado como
      contenido del documento, las primeras 4 páginas como imagen y la ruta de una
      copia local para las herramientas del agente (`pdf`, `image`, `read`).
- [x] **Lectura de PDF con PDFium** (`ai_bridge/PdfDoc.cs`, `bblanchon.PDFium.Win32`
      desde nuget.org): texto por página y render de páginas; PDF dañados o con
      contraseña dan un error claro.
- [x] **Modelos sin visión**: si el gateway rechaza las imágenes, se reenvía una vez
      solo con el texto. Probado con el agente real `cerebro` (modelo de texto): leyó
      el PDF de ejemplo y propuso la gráfica y la nota correctas.
- [x] **Módulo «Gráficas»** del laboratorio (18.º módulo): hasta 4 funciones con
      raíces, extremos y cortes; paramétricas, polares, superficies y puntos.
      `load_spec` lo configura de una vez.
- [x] **Acciones nuevas** del chat: `grafica`, `lab` y `nota`; **📝 Notas del
      proyecto** guardadas en el `.mforge`. API: `lab_plot`, `write_note`
      (propuesta) y `get_notes`.
- [x] Pruebas: `mfadjuntos` (39, con un gateway falso que comprueba el JSON enviado
      y el reenvío) y 20 más de Gráficas en `mflabtest`.

## ✅ Multímetro digital, integrados DIP y cortocircuitos
- [x] Solver de circuito **no lineal** (MNA + Newton-Raphson, `electronics/CircuitSolver.cs`):
      LED como diodo de Shockley con resistencia serie, baterías con resistencia
      interna, cables como elementos con corriente propia, gmin para nodos flotantes.
- [x] `NodeNetlist` (geometría 3D → nodos: tiras de la protoboard, patas insertadas,
      cables y sondas) y `CircuitRuntime` (circuito vivo en edición y simulación).
- [x] **Multímetro 3D** (`DMMController`, `ProbeInteractionSystem`, `ElectronicsVisuals`):
      LCD de 7 segmentos por shader, selector giratorio, bornes, sondas con cable de
      cuerda, snap magnético 90°/45°, V⎓, V~ (RMS), A⎓ con fusibles de 400 mA y 10 A,
      Ω (solo desenergizado, «Err»), continuidad con pitido sintético.
- [x] **Cortocircuito crítico** (`ShortCircuitFX`): chispas y humo con partículas GPU,
      cable incandescente (shader de cuerpo negro + modelo térmico I²R), desconexión
      por protección térmica, aviso y «Rearmar». LED y resistencias que se queman.
- [x] **Protoboard multipín** (`BreadboardSnap`): inserción con snap en los agujeros,
      DIP obligado a cruzar el canal central, NE555 (DIP-8) y Arduino Nano (DIP-30),
      jerarquía padre-hijo (en edición y como cuerpo compuesto en simulación).
- [x] Corrección: los puentes largos ya no atraviesan la protoboard (el cable nunca
      sale por la cara inferior de una pieza).
- [x] API: `get_circuit_state` y `measure_voltage`. Ejemplos 10 y 11. Pruebas `mfmulti` (71).

## ✅ Cochera, texturas reales, protoboard real y selección de uniones
- [x] Skill `mechaforge` probada con el agente **Cerebro**: leyó la escena, listó
      piezas, propuso un engranaje (pendiente de confirmación), consultó su estado y
      ejecutó el análisis con datos reales de la API.
- [x] Entorno **Cochera (exterior)** (`rendering/GarageScene.gd`): nave con portón
      abierto, HDRI real (Poly Haven, CC0), mobiliario y zona de pruebas con colisión
      (rampa, tope, conos), sonda de reflejos, lámparas y día/noche.
- [x] **Texturas fotográficas** ambientCG (CC0, `rendering/TextureSets.gd`) para toda
      la electrónica y los actuadores y para aluminio, acero, ABS, caucho, madera y
      hormigón (`project/assets/CREDITOS.md`).
- [x] **Protoboard MB-102** de 830 puntos con medidas reales: agujeros dibujados y
      terminales desde la misma tabla; serigrafía de filas y columnas.
- [x] **Selección de uniones**: número en 3D igual al de la lista, clic en fila o en
      el marcador, resaltado de piezas, detalle, encuadre y borrado con `Supr`.
- [x] Cables apoyados más suaves (relajación Laplaciana).
- [x] Pruebas `mfentorno` (24/24).

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
