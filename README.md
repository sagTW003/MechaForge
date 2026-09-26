# MechaForge

**Simulador virtual de construcción mecatrónica e ingeniería** — un "sandbox de
ingeniería" para diseñar, ensamblar, programar y probar mecanismos, robots,
vehículos, grúas, estructuras, transmisiones y sistemas de control, con física
realista y gráficos de alta calidad.

> Estado: **Fase 1 completada** (base del proyecto, entorno 3D, cámara orbital,
> perfiles gráficos automáticos, colocación de piezas con snapping, guardar/cargar).
> Ver [docs/HOJA_DE_RUTA.md](docs/HOJA_DE_RUTA.md).

![Demostración Fase 1](docs/demo_fase1.png)

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
| Ayuda | `H` o `F1` |

Lista completa en [docs/ATAJOS.md](docs/ATAJOS.md).

## Arquitectura

Modular por carpetas dentro de `project/`:

| Módulo | Responsabilidad |
|---|---|
| `core/` | Escena, piezas (definidas por datos), materiales, unidades SI, cálculo (C#) |
| `physics/` | *(Fase 2)* Uniones, motores, engranajes |
| `electronics/` | *(Fase 3)* Cableado y solver eléctrico |
| `control/` | *(Fase 3)* Microcontrolador virtual, PID, scripts |
| `rendering/` | Perfiles gráficos, entorno, shaders |
| `ui/` | Interfaz, cámara orbital, controlador principal |
| `ai_bridge/` | *(Fase 4)* Puente con OpenClaw |
| `io/` | Serialización de proyectos (JSON) |

Detalle en [docs/ARQUITECTURA.md](docs/ARQUITECTURA.md).

### Piezas definidas por datos

Cada pieza es un objeto JSON en `project/parts/`. **Para añadir una pieza nueva,
crea o edita un `.json`** — no hace falta tocar código. Ejemplo en
`project/parts/estructural.json`.

## Integración con OpenClaw (IA personalizada) — *Fase 4*

MechaForge se conectará a tu instancia local de **OpenClaw** (gateway en
`127.0.0.1:18789`, endpoint compatible con OpenAI y bridge MCP) mediante un
módulo desacoplado `ai_bridge`. La dirección, puerto y token irán en
`project/ai_bridge/openclaw_config.json` (plantilla en
`openclaw_config.example.json`), **nunca en el código**. La app funciona
completa sin IA; la integración es opcional. Ver
[docs/INTEGRACION_OPENCLAW.md](docs/INTEGRACION_OPENCLAW.md).

## Formato de proyecto

Los proyectos se guardan como JSON legible con extensión `.mforge`
(ver `project/io/ProjectSerializer.gd`).

## Licencia

Proyecto personal. Godot Engine se distribuye bajo licencia MIT.
