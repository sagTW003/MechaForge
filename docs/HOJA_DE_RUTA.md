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

## ⏳ Fase 4 — Integración OpenClaw
- [ ] Puente `ai_bridge` (gateway local + herramientas MCP/JSON-RPC).
- [ ] Panel de chat lateral; vistas previas "fantasma" con confirmación.
- [ ] Diagnóstico y generación de código usando el estado real de la escena.

## ⏳ Fase 5 — Análisis avanzado
- [ ] Mapa de esfuerzos por carga, rotura opcional, estabilidad/vuelco.
- [ ] Plantillas (brazo 4 GDL, seguidor de línea, grúa, puente, pinza).
- [ ] Importación STL/OBJ/GLTF como piezas; exportar BOM.

## ⏳ Fase 6 — Pulido y empaquetado
- [ ] Optimización en este hardware, perfiles finos.
- [ ] Ejecutable + instalador/carpeta portable para Windows.
