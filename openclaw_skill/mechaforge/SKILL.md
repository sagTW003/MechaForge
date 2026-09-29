---
name: mechaforge
description: Controlar el simulador MechaForge (construcción mecatrónica) desde OpenClaw — leer la escena y la telemetría, analizar diseños y proponer piezas, uniones, cambios y programas de microcontrolador.
---

# MechaForge — simulador de construcción mecatrónica

MechaForge expone una **API local JSON-RPC 2.0** en `http://127.0.0.1:18790` (solo
esta máquina). Úsala cuando el humano te pida construir, revisar o diagnosticar algo
en MechaForge. Si `curl` falla con conexión rechazada, MechaForge no está abierto:
díselo al humano.

## Autenticación

El token está en el archivo de configuración de MechaForge (nunca lo copies en
mensajes ni lo guardes en otro sitio):

```bash
TOKEN=$(python -c "import json,os;print(json.load(open(os.path.expandvars(r'%APPDATA%\Godot\app_userdata\MechaForge\mechaforge_api.json')))['token'])")
```

PowerShell:

```powershell
$TOKEN = (Get-Content "$env:APPDATA\Godot\app_userdata\MechaForge\mechaforge_api.json" | ConvertFrom-Json).token
```

## Llamar a una herramienta

```bash
curl -s -X POST http://127.0.0.1:18790/rpc \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"get_scene_state","params":{}}'
```

`GET /tools` devuelve la lista completa con su esquema JSON.

## Herramientas

| Método | Para qué |
|---|---|
| `get_scene_state` | Piezas (uid, def_id, material, pos, rot, masa), uniones, cables, si simula |
| `list_parts` | Catálogo de piezas (`def_id`) y materiales disponibles |
| `get_telemetry` | Posición/velocidad de piezas, consigna/medida/temperatura de motores, consumo |
| `analyze_design` | Masa, centro de masa, estabilidad (margen de vuelco), esfuerzos, autonomía |
| `add_part` | `{"def_id","material","pos":[x,y,z],"rot_deg":[x,y,z]}` (metros; el suelo es y=0) |
| `connect_parts` | `{"a","b","union":"fija|bisagra|deslizadera|rotula|engranaje","eje":"X|Y|Z","motor":true}` |
| `set_property` | `{"uid","material","dims_mm":{...},"pos":[...]}` |
| `remove_part` | `{"uid"}` |
| `write_controller_script` | `{"script"}` programa del microcontrolador (ver abajo) |
| `run_simulation` / `stop_simulation` | Iniciar / detener la física |
| `get_proposal_status` | `{"id"}` → `pending`, `applied` o `discarded` |
| `get_circuit_state` | Circuito vivo: fuentes, LED (mA, encendido/quemado), cortocircuito, piezas insertadas en la protoboard y lectura del multímetro |
| `measure_voltage` | `{"a":"uid:terminal","b":"uid:terminal"}` → tensión entre dos puntos (solo lectura) |
| `lab_*` | Laboratorio matemático 3D (EDPs, métodos numéricos, análisis complejo, campos vectoriales): ver la skill **mechaforge-laboratorio** |

## Reglas importantes

- **Los cambios no se aplican solos.** `add_part`, `connect_parts`, `set_property`,
  `remove_part` y `write_controller_script` devuelven `pending_confirmation` y un
  `proposal_id`: MechaForge muestra una vista previa fantasma y **el humano decide**
  (Aplicar/Descartar). Consulta `get_proposal_status` antes de dar algo por hecho.
- Usa solo `def_id` existentes (`list_parts`). Unidades SI: metros, kg, rad/s.
- Una pieza apoyada en el suelo tiene su centro a media altura (`y = alto/2`).
- Para diagnosticar ("¿por qué se vuelca?"), llama primero a `analyze_design` y, si
  simula, a `get_telemetry`; justifica con los datos (centro de masa, margen, esfuerzos).
- Si el humano tiene abierto el **Laboratorio matemático**, las herramientas de la
  escena responden con un error que pide `lab_close`. No lo cierres por tu cuenta:
  pregúntale si quiere volver a MechaForge.
- Circuitos: `get_circuit_state` informa de cortocircuitos, LED quemados, fusibles del
  multímetro y qué patas del integrado caen en cada agujero de la protoboard (los
  DIP deben cruzar el canal central). Úsalo antes de proponer cambios eléctricos.

## Programa del microcontrolador

Líneas `variable = expresión`, evaluadas cada ciclo; la última es la consigna de la
unión elegida y `m1`, `m2`… son consignas de las uniones con control (en orden).
Variables: `t` (s), `x` (medida), `dt` y sensores: `dist1` (ultrasonido, m),
`lidar1` (m), `enc1` (°), `imu1_pitch`/`imu1_roll` (°), `fin1` (0/1), `fuerza1` (N),
`linea1` (0/1). Funciones: `sin`, `cos`, `abs`, `clamp`, `min`, `max`… y
`a if condición else b`.

```
base = 6
err = linea1 - linea2
m1 = base - 7 * err
m2 = base + 7 * err
output = m1
```
