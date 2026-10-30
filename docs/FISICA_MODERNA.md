# Física moderna en el Laboratorio: propuesta de arquitectura (Fase 1)

Simuladores de **partículas y mecánica cuántica** y de **teoría de cuerdas** dentro del
Laboratorio matemático de MechaForge (Godot 4.7 .NET), según
`prompt-simuladores-fisica-robusto.md`. Estado: **pendiente de aprobación**.

## 1. Decisiones

| Tema | Decisión | Alternativa descartada y por qué |
|---|---|---|
| Dónde | Pilar nuevo «Física moderna» (`MathLab.PILLARS[4]`) con varios `LabModule` | App web aparte: proyecto nuevo, sin la UI, la API de OpenClaw ni las pruebas existentes |
| Partición | El «módulo 1» del encargo son 3 módulos del Laboratorio (`hidrogeno`, `particulas`, `bateria`) y el «módulo 2» son 2 (`cuerdas`, `compactas`) | Un único módulo con modos: un panel de controles inmanejable |
| Carga diferida | La que ya existe: `MathLab.open_module()` hace `load()` del script al abrirlo; los kernels de GPU se compilan en `setup()` | — |
| Física (dominio) | C# puro sin nodos ni escena en `mathlab/fisica/dominio/`, en doble precisión, con funciones sin estado (arrays de entrada y de salida) detrás de un autoload `Fisica` (C# `Node`), como `Electronics` y `MeshTools` | Objetos `RefCounted` de C# por simulación: hay que liberarlos a mano (fallo de cierre de la 0.4.0) |
| Cálculo pesado | **GPU (RTX 5060) con compute shaders de `RenderingDevice`**: GLSL en `.glsl` (`#[compute]`) que Godot importa como `RDShaderFile`. Medido: Coulomb O(N²) con 10 000 cargas en **0,92 ms**, error 1,7·10⁻⁶ frente a doble precisión | Solo CPU: el mismo cálculo tarda ~3,6 s en GDScript y decenas de ms en C# en paralelo |
| Sin GPU | Cada kernel tiene una versión de referencia en C# (`dominio/`). Sin `RenderingDevice` (pruebas sin ventana o renderizador Compatibility) se usa esa, con menos entidades | Exigir GPU: las pruebas sin ventana no podrían correr |
| GPU → dibujo | Primero `RenderingDevice` local y lectura a CPU (10 000 partículas ≈ 160 KB por frame). Para volúmenes grandes (|ψ|² 128³ ≈ 16 MB) se usa el `RenderingDevice` principal con `Texture3DRD`, sin copia | Siempre sin copia: más complejo (hilo de render) sin necesidad para las partículas |
| Dibujo | `MultiMeshInstance3D` para partículas y cuerdas (sin un nodo por entidad); cuerdas evaluadas en el *vertex shader* a partir de sus modos; |ψ|² con *raymarching* en un shader propio (fase = color, con leyenda y valor en el tooltip para no depender solo del color) | `GPUParticles3D`: menos control de los datos; `FogVolume`: no colorea por fase |
| Unidades | Cuántica en **unidades atómicas** (ħ = mₑ = e = 4πε₀ = 1; 1 Eₕ = 27,211386 eV); partículas en **MeV** y fm; cuerdas en unidades de √α′. Las constantes y conversiones viven en `Unidades.cs` con su fuente (CODATA) | Tipos por magnitud (`Energy`, `Length`…): mucho código para poco riesgo; se usa un sufijo en el nombre (`e_eV`, `r_fm`) y pruebas |
| Datos | Tabla PDG en `fisica/datos/particulas_pdg.json` con masa, carga, espín, color y números B/L, más la cita de cada valor. Se verifican contra la fuente al introducirlos, sin escribir ninguno de memoria | — |

## 2. Capas y flujo de datos

```mermaid
flowchart LR
  UI["LabUI + panel «Modelo y límites»<br/>(GDScript)"] --> M["LabModule del pilar<br/>(GDScript: escena, controles, step)"]
  M --> S["Simulación: paso fijo, semilla,<br/>vigilancia de NaN (GDScript)"]
  S --> F["Fisica (autoload C#)<br/>dominio en doble precisión"]
  S --> G["GpuCompute: kernels .glsl<br/>en la RTX 5060"]
  G -. "sin GPU" .-> F
  G --> R["Render: MultiMesh, shaders,<br/>Texture3DRD"]
  F --> R
  API["LabApi / OpenClaw"] --> M
  T["tests/FisicaTests.gd (mffisica)"] --> F
  T --> G
```

La física (`Fisica`, `dominio/`) no conoce la escena: las pruebas la llaman sin interfaz.
El render solo lee buffers. OpenClaw maneja los controles por `LabApi` sin código extra.

## 3. Contratos

**`LabModule`** (se añaden métodos con valor por defecto; los 16 módulos actuales no cambian):

```gdscript
## [{subsistema, nivel: "exacto"|"aproximado"|"ilustrativo", modelo, ecuaciones, unidades, referencias}]
func fidelidad() -> Array: return []
## Estado guardable (JSON); cargar() devuelve "" o el motivo del rechazo.
func estado() -> Dictionary: return {}
func cargar(_d: Dictionary) -> String: return ""
## {entidades, fisica_ms} para el panel de métricas.
func metricas() -> Dictionary: return {}
## Liberar RIDs de GPU al desmontar.
func liberar() -> void: pass
```

**`Fisica`** (C#, sin estado; ejemplos):

```csharp
double HydrogenEnergy_eV(int n);                                  // −13,605693 eV / n²
Dictionary Conservation(string[] entrada, string[] salida);         // {ok, viola: [...]}
PackedFloat64Array HydrogenDensity(int n, int l, int m, int res, double size_a0);
PackedFloat64Array SpinChainStep(PackedFloat64Array psi, Dictionary h, double dt);
Dictionary StringSpectrum(string tipo, string contorno, int nMax); // α′M² = N − a
```

**`GpuCompute`** (GDScript): `available() -> bool`,
`kernel(ruta_glsl) -> RID`, `run(kernel, buffers, push_constants, grupos)`, `read(buffer)`,
`liberar()`. Comprueba en la primera ejecución que el kernel coincide con la referencia de C#.

## 4. Estructura

```
project/mathlab/fisica/
  Fisica.cs                 autoload (puente GDScript ↔ C#)
  GpuCompute.gd             RenderingDevice local: kernels, buffers, liberación
  dominio/                  C# puro: Unidades, Particulas (tabla), Conservacion,
                            Hidrogeno, Cornell, Decaimientos, Nucleos, CadenaEspines,
                            Cuerda, Compactas
  datos/particulas_pdg.json
  kernels/*.glsl            coulomb, schrodinger3d, …
  shaders/*.gdshader        nube orbital, cuerda, brana, rejilla espacio-temporal
project/mathlab/modules/    HidrogenoModule, ParticulasModule, BateriaModule,
                            CuerdasModule, CompactasModule
project/tests/FisicaTests.gd   suite mffisica (+ «gpu» con ventana, + «bench»)
```

## 5. Nivel de fidelidad previsto

| Subsistema | Nivel | Modelo |
|---|---|---|
| Orbitales y energías del hidrógeno | Exacto | Solución analítica no relativista (sin estructura fina) |
| Schrödinger 3D de paquetes | Exacto (numérico) | Esquema de Visscher 3D (el del 2D actual), norma conservada con tolerancia medida |
| Fuerzas entre cargas | Aproximado | Coulomb/Lorentz clásicos con suavizado ε, sin radiación |
| Fuerza fuerte | Aproximado | Potencial de Cornell V = −4αₛ/3r + σr |
| Hadronización | Ilustrativo | Formación de pares visual, sin cálculo |
| Decaimientos débiles, α, β, γ | Aproximado | Vidas medias y fracciones del PDG y de tablas nucleares; cinemática simplificada |
| Leyes de conservación | Exacto | Carga, números B y L, energía en cada evento |
| Configuraciones electrónicas | Aproximado | Regla de Madelung con las excepciones tabuladas |
| Estabilidad nuclear | Aproximado | Fórmula semiempírica de Weizsäcker |
| Batería cuántica (N ≤ 12) | Exacto (numérico) | Cadena de Heisenberg: evolución unitaria con hamiltoniano disperso; ergotropía de estado puro ⟨H⟩ − E₀ (E₀ por Lanczos) |
| Cuerda clásica libre (abierta, cerrada, N/D) | Exacto | Desarrollo en modos de la ecuación de ondas |
| Espectro de masas | Exacto (en la teoría libre) | α′M² = N − a (bosónica a = 1; supercuerda NS/R) |
| Dimensiones en un toro | Exacto (en la teoría libre) | Masas de Kaluza-Klein y de enrollamiento |
| Calabi-Yau (quíntica) | Ilustrativo | Proyección de una sección real |
| D-branas | Aproximado/ilustrativo | Condiciones de Dirichlet exactas; la membrana es visual |
| Curvatura del espacio-tiempo y g_s | Ilustrativo | Rejilla deformada por la energía; sin gravedad real |

## 6. Rendimiento

Hardware de referencia: Ryzen 7 5700G, **RTX 5060** (Vulkan 1.4, la usa ya Godot y el
ejecutable), 28 GB, 1080p. Perfil «Bajo»: Radeon integrada o sin `RenderingDevice`.
Objetivos: 60 FPS con 10 000 partículas (Coulomb en GPU < 2 ms) y 1 000 cuerdas de 128
puntos (en el *vertex shader*). Lo mide `-- mffisica bench` en la RTX 5060.

## 7. Riesgos

1. **float32 en la GPU**: tolerancias relativas de ~10⁻⁶; las pruebas de precisión se hacen
   con la referencia de C# en doble y la GPU se compara contra ella.
2. **Sin `RenderingDevice` en las pruebas sin ventana**: la parte de GPU se prueba en una
   pasada con ventana (`-- mffisica gpu`).
3. **Fugas de RIDs de GPU**: `liberar()` al desmontar y la prueba de montar y desmontar 20
   veces cada módulo (ya existe para los módulos con `FieldSim`).
4. **Datos físicos**: cada valor con su fuente; ninguno escrito de memoria.
5. **Alcance de «materia exótica» y de los tipos de cuerda**: se acota a superposiciones de
   modos con su masa calculada; los tipos I/IIA/IIB/heterótica cambian el espectro y las
   condiciones permitidas, no simulan dinámica.

## 8. Fase 2 (núcleo compartido), si se aprueba

`Fisica.cs` con `Unidades`; `GpuCompute.gd` con la prueba de Coulomb GPU frente a C#;
contratos de `LabModule`; panel «Modelo y límites» y panel de métricas del Laboratorio;
paso fijo, semilla y vigilancia de NaN; guardado del módulo abierto en el `.mforge`
(«laboratorio»: módulo, versión y estado, con validación) y deshacer en el Laboratorio;
suite `mffisica`.
