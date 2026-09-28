# Integración con OpenClaw — plan (Fase 4)

Este documento recoge lo detectado sobre la instalación local de OpenClaw en el
Paso 0, para diseñar el puente `ai_bridge` **sin inventar la API**.

## Lo detectado

- **OpenClaw 2026.6.34**, instalado por npm.
  Ejecutable/CLI: `openclaw` → `AppData\Roaming\npm\node_modules\openclaw\dist\index.js`.
- **Gateway local activo** en `127.0.0.1:18789` (bind *loopback*, solo local).
- **Autenticación por token** (definido en `~/.openclaw/openclaw.json`, sección
  `gateway.auth.token`). **El token no se copia al repositorio**: se leerá desde
  la configuración local del puente.
- **Endpoint compatible con OpenAI** habilitado
  (`gateway.http.endpoints.chatCompletions`).
- La CLI expone `openclaw mcp` (**bridge MCP**) y `openclaw agent`
  (ejecutar un turno de agente por el gateway).
- Agentes configurados: por defecto **"Cerebro" 🧠**; también **"Viernes"** y
  agentes con perfil `coding`.

## Estrategia de integración (dos direcciones)

1. **MechaForge → OpenClaw (chat / diagnóstico)**
   Cliente HTTP al endpoint compatible con OpenAI del gateway
   (`http://127.0.0.1:18789`, cabecera `Authorization: Bearer <token>`), para el
   panel de chat lateral y las consultas de diagnóstico que incluyen el estado
   real de la escena.

2. **OpenClaw → MechaForge (herramientas)**
   Exponer MechaForge como **servidor MCP local** (o JSON-RPC sobre WebSocket en
   `127.0.0.1`) y registrarlo con `openclaw mcp`, ofreciendo las herramientas del
   proyecto con esquema JSON:
   - `get_scene_state`, `get_telemetry`, `analyze_design`, `get_circuit_state`, `measure_voltage`
   - `add_part`, `connect_parts`, `set_property`, `remove_part`
   - `write_controller_script`, `run_simulation`, `stop_simulation`

## Seguridad
- Conexión **solo local** (loopback).
- Todo cambio propuesto por la IA se muestra como **vista previa "fantasma"** y
  requiere **confirmación** antes de aplicarse (ver `MaterialLibrary.get_ghost`).
- Historial de acciones de la IA **reversible** (mismo sistema de deshacer).
- Si OpenClaw no responde, la app funciona completa y muestra el estado de conexión.
- **La configuración de OpenClaw no se modifica** sin autorización explícita.

## Configuración
La conexión se define en `project/ai_bridge/openclaw_config.json` (plantilla:
`openclaw_config.example.json`). Ese archivo real está en `.gitignore`.


## Estado implementado (API de herramientas)

- **MechaForge → OpenClaw**: panel de chat (`ai_bridge/OpenClawBridge.gd`) contra el
  endpoint compatible con OpenAI del gateway, con el estado de la escena como contexto.
- **OpenClaw → MechaForge**: `ai_bridge/ToolServer.gd` expone una **API JSON-RPC 2.0
  sobre HTTP** en `127.0.0.1:18790` (solo loopback, token Bearer en
  `user://mechaforge_api.json`, generado la primera vez y fuera del repositorio).
  Las herramientas (`ai_bridge/SimulatorApi.gd`) son las del documento del proyecto:
  `get_scene_state`, `add_part`, `connect_parts`, `set_property`, `remove_part`,
  `write_controller_script`, `run_simulation`, `stop_simulation`, `get_telemetry`,
  `analyze_design` (+ `list_parts`, `get_proposal_status`).
- Se eligió HTTP (en lugar de WebSocket) porque las *skills* de OpenClaw usan `curl`;
  así un agente puede usar MechaForge sin código adicional.
- **Seguridad**: toda herramienta que modifica la escena devuelve
  `pending_confirmation` y muestra la propuesta como **piezas fantasma** con
  **Aplicar/Descartar** en el panel de IA; lo aplicado entra en deshacer/rehacer.
- **Skill lista para instalar**: `openclaw_skill/mechaforge/SKILL.md`. Para usarla,
  copia la carpeta `mechaforge` a `~/.openclaw/skills/` (no se instala sola: la
  configuración de OpenClaw solo se cambia con tu permiso).
- Pruebas: `-- mffinal` hace peticiones HTTP reales (health, 401 sin token, /tools,
  propuesta → vista previa → aplicar, estado, análisis, simulación, telemetría).
