# Arquitectura — MechaForge

## Principios
- **Modular y desacoplado**: cada módulo tiene una responsabilidad clara y se
  comunica por señales (`Config` actúa como bus de eventos).
- **Definido por datos**: las piezas son archivos JSON; añadir contenido no
  requiere tocar código.
- **Unidades SI** en toda la lógica interna; el formateo a texto legible está
  aislado en `core/Units.gd`.
- **GDScript** para interfaz y herramientas; **C#** (.NET 8) para cálculo
  intensivo (empieza con `core/MassProperties.cs`).

## Módulos (dentro de `project/`)

### `core/` — Modelo de datos y cálculo
- `Config.gd` *(autoload)* — ajustes globales (rejilla, snapping) y bus de señales.
- `Units.gd` — formateo de magnitudes SI.
- `MaterialLibrary.gd` *(autoload)* — materiales con densidad, fricción, límites
  y aspecto PBR; genera `StandardMaterial3D` y materiales "fantasma".
- `PartLibrary.gd` *(autoload)* — carga y cataloga las definiciones JSON de piezas.
- `PartInstance.gd` — una pieza colocada: construye su malla procedural, cuerpo
  de selección, calcula su masa y se serializa.
- `MassProperties.cs` — cálculo de masa e inercia (módulo C#).
- `MeshMass.cs` — volumen, área, centroide e inercia de una malla estanca
  (teorema de la divergencia) para los modelos importados.

### `vr/` — Visor VR casero
- `Optics.gd` — óptica de lente delgada del visor (imagen virtual, campo de visión,
  píxeles por grado, IPD y avisos).
- Piezas en `parts/vr.json`; el bus I²C está en `electronics/I2CBus.gd` y las funciones
  `i2c_…` del programa en `control/McuIo.gd`.

### `physics/` — Simulación (Fase 2)
- `Simulator.gd` — convierte las piezas en `RigidBody3D` (Jolt), crea las uniones
  y las gobierna cada paso físico. Uniones: **fija/deslizadera/rótula** con
  `Generic6DOFJoint3D` (límites), **bisagra** con `HingeJoint3D` (motor con curva
  torque–velocidad y límites) y **engranaje** por acoplamiento cinemático de
  velocidad. Calcula y muestra el **centro de masa** y expone **telemetría**.
- `core/Connection.gd` — modelo de datos serializable de una unión.

> Nota técnica: el motor angular de `Generic6DOFJoint3D` no es fiable con Jolt,
> por eso las bisagras motorizadas usan `HingeJoint3D`. Su eje de giro es el eje
> **Z local** del joint (convención Bullet/Jolt), por eso se orienta con `_axis_basis_z`.

### `electronics/` y `control/` — Electrónica y control (Fase 3, C#)
- `electronics/ElectricalSolver.cs` — solver de circuitos DC por Análisis Nodal
  Modificado (Ohm/Kirchhoff): tensiones, corrientes, potencia, autonomía.
- `control/PidController.cs` — PID discreto con anti-windup y límites.
- `electronics/Electronics.cs` — **autoload** que expone ambos a GDScript con
  tipos simples (GDScript no puede referenciar clases C# por nombre de forma
  fiable, así que toda la interop pasa por este servicio).
- `ui/LiveGraph.gd` — osciloscopio/gráfica dibujada con `_draw()`.
- La integración vive en `Simulator`: cada bisagra motorizada puede llevar un PID
  (posición/velocidad); el consumo se calcula tratando cada motor como carga.

### `rendering/` — Gráficos
- `GraphicsProfiles.gd` *(autoload)* — detecta la GPU, elige perfil
  (Bajo/Medio/Alto/Ultra), aplica ajustes al `Environment` y `Viewport`, y hace
  escalado dinámico de resolución.
- `floor_grid.gdshader` — rejilla de taller estilo CAD sobre el suelo.

### `ui/` — Interfaz y cámara
- `Main.gd` — controlador principal: construye el entorno 3D y la UI, gestiona
  colocación, selección, propiedades, deshacer/rehacer y archivos.
- `CameraOrbit.gd` — cámara orbital tipo CAD.

### `io/` — Persistencia
- `ProjectSerializer.gd` — guardar/cargar proyectos en JSON (`.mforge`).

### Pendientes (fases siguientes)
- `electronics/` — cableado y solver eléctrico.
- `control/` — microcontrolador virtual, PID.
- `ai_bridge/` — puente con OpenClaw.

## Deshacer/Rehacer
Basado en **comandos** (`add`, `remove`, `transform`) con dos pilas. Cada comando
sabe aplicarse y revertirse, lo que mantiene el historial ligero y reversible —
incluido, en la Fase 4, el historial de acciones de la IA.

## Selección con el ratón
Cada `PartInstance` incluye un `StaticBody3D` en una capa de colisión dedicada
(`PICK_LAYER`). La selección usa un raycast físico contra esa capa; el mismo
cuerpo servirá de base para la física de la Fase 2.

## Formato de proyecto (`.mforge`)
```json
{
  "formato": "mechaforge",
  "version": 1,
  "grid_mm": 10.0,
  "piezas": [
    { "uid": "...", "def_id": "perfil_2020_200", "material": "aluminio",
      "pos": [x, y, z], "rot": [x, y, z] }
  ]
}
```
