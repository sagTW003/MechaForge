---
name: mechaforge-laboratorio
description: Usar el Laboratorio matemático 3D de MechaForge desde OpenClaw — abrir módulos (ondas, calor, Schrödinger, raíces, sistemas, optimización, interpolación, integración, EDP numérica, coloreado de dominio, mapeos conformes, fractales, campos vectoriales, Gauss/Stokes), cambiar funciones y parámetros, leer resultados y explicar la matemática con datos.
---

# MechaForge — Laboratorio matemático 3D

El laboratorio muestra en 3D, en tiempo real:
- ecuaciones en derivadas parciales;
- métodos numéricos;
- análisis complejo;
- campos vectoriales.

Úsalo cuando el humano quiera **ver o entender** algo de matemáticas, por ejemplo:
- "enséñame el efecto túnel";
- "¿dónde tiene polos esta función?";
- "¿por qué diverge Jacobi?";
- "compara Newton con bisección".

MechaForge tiene que estar abierto. Se controla con la misma API local que la skill
**mechaforge**: JSON-RPC 2.0 en `http://127.0.0.1:18790`, solo en esta máquina. Si
`curl` da conexión rechazada, díselo al humano.

## Conexión

El token está en el archivo de configuración de MechaForge. Nunca lo muestres ni lo
guardes en otro sitio.

```bash
TOKEN=$(python -c "import json,os;print(json.load(open(os.path.expandvars(r'%APPDATA%\Godot\app_userdata\MechaForge\mechaforge_api.json')))['token'])")
mf() { local p="${2:-}"; [ -z "$p" ] && p='{}'; curl -s -X POST http://127.0.0.1:18790/rpc -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json; charset=utf-8" --data-binary "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$p}"; echo; }
mf lab_get_state
mf lab_open '{"modulo":"schrodinger"}'
```

PowerShell:

```powershell
$TOKEN = (Get-Content "$env:APPDATA\Godot\app_userdata\MechaForge\mechaforge_api.json" | ConvertFrom-Json).token
function mf($m, $p = @{}) { $b = @{jsonrpc="2.0"; id=1; method=$m; params=$p} | ConvertTo-Json -Depth 8 -Compress; Invoke-RestMethod -Method Post -Uri http://127.0.0.1:18790/rpc -Headers @{Authorization="Bearer $TOKEN"} -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($b)) }
mf lab_open @{modulo="schrodinger"}
```

## Herramientas

| Método | Parámetros | Para qué |
|---|---|---|
| `lab_list_modules` | — | Los 14 módulos: `id`, pilar, nombre y descripción |
| `lab_open` | `{"modulo":"id"}` | Abre el laboratorio en ese módulo, o cambia de módulo si ya está abierto. Si estaba cerrado responde `"status":"abriendo"`: espera 1 s y llama a `lab_get_state` |
| `lab_get_state` | — | Módulo, fórmula, `info` (lecturas en vivo), `puntos_criticos` (con `x, y, z`) y `parametros` (cada control con `id`, `nombre`, `tipo`, `valor`, rango u `opciones`) |
| `lab_set_param` | `{"nombre":"…","valor":…}` | Mueve un control igual que el humano (ver abajo) |
| `lab_control` | `{"accion":"…"}` | Controles generales (ver abajo) |
| `lab_sample` | `{"x":…,"y":…}` | Lectura en un punto; es el mismo texto que el tooltip flotante. Solo lectura |
| `lab_perturb` | `{"x":…,"y":…}` | Equivale a un clic con «✋ Perturbar»: pulso, calor, barrera, punto inicial… según el módulo |
| `lab_capture` | — | Guarda una captura PNG de la ventana y devuelve la ruta en `archivo`. Si puedes ver imágenes, úsala para describir lo que ve el humano |
| `lab_close` | — | Vuelve a MechaForge |

Detalles de `lab_set_param`:
- `nombre` acepta el `id` (`"p3"`), el nombre exacto, `"Sección/Nombre"` o el
  principio del nombre (`"Altura"`, `"Momento"`).
- Los símbolos de los botones (▶ ⏩ 🚀 ⟲) no hacen falta. Con prefijos ASCII evitas
  problemas de codificación en la consola.
- El `valor` depende del tipo de control:

| Tipo | Valor |
|---|---|
| `deslizador` / `numero` | Número; se limita al rango |
| `opcion` | Texto de la opción (basta una parte: `"barrera"`) o su índice |
| `casilla` | `true` o `false` |
| `expresion` | La fórmula; si no es válida devuelve el error del analizador |
| `boton` | Se ignora: lo pulsa |

Acciones de `lab_control`:
- `pausar`, `reanudar`, `reiniciar`;
- `encuadrar`: la cámara recorre los puntos críticos;
- `vista_perspectiva`, `vista_superior` (mapa 2D), `vista_isometrica`;
- `velocidad` con `"valor"`: 0.25, 0.5, 1, 2, 4 u 8.

## Reglas

- **Abrir el laboratorio cambia la ventana del humano.** Su escena de MechaForge se
  conserva intacta, pero ábrelo solo si te lo pide o lo acepta.
- Al terminar, pregúntale si quiere volver (`lab_close`); no lo cierres por tu cuenta.
  Mientras está abierto, las herramientas de la escena (`get_scene_state`,
  `add_part`…) responden con un error que pide `lab_close`.
- Los cambios del laboratorio solo afectan a la visualización. No tocan el proyecto,
  se aplican al momento y cada uno se anuncia en la barra de estado como
  «🤖 OpenClaw: …».
- Lee `lab_get_state` antes de cambiar nada: los nombres, rangos y opciones salen de
  ahí. No los inventes.
- Los módulos de EDP evolucionan en el tiempo (`evoluciona_en_el_tiempo: true`). Tras
  un cambio, espera 1–4 s (`sleep 3`) antes de leer `info` o `lab_sample`.
- Explica con los números reales de `info`, `puntos_criticos` y `lab_sample`, y
  relaciónalos con la teoría (orden de convergencia, estabilidad, índice de un polo…).
- `x, y` de `lab_sample` / `lab_perturb` son las coordenadas del tooltip de cada
  módulo (tabla de abajo). Fuera de la superficie visible devuelven un error.

## Expresiones

Admiten:
- multiplicación implícita (`2x`, `3(x+1)`);
- potencias con `^` o `**`, y valor absoluto `|x|`;
- constantes `pi`, `e`, `tau` e `i` (unidad imaginaria en modo complejo).

Funciones:
- reales: `sin cos tan asin acos atan atan2 sinh cosh tanh exp log ln log10 sqrt cbrt
  abs floor ceil sign min max pow mod sec csc cot`;
- complejas: `sin cos tan sinh cosh tanh exp log sqrt abs conj re im arg pow`.

Las fórmulas se compilan a GLSL y se evalúan en la GPU.

## Módulos

| id | Qué muestra | Controles clave | Coordenadas `x, y` · Perturbar |
|---|---|---|---|
| `onda` | Membrana ∂²u/∂t² = c²∇²u (FDTD), energía, modos normales | Membrana, Frontera (fija/libre/absorbente), Velocidad de onda c, Amortiguamiento, Interferencia (2 fuentes), m, n, Excitar el modo | [−1, 1]² · pulso gaussiano |
| `calor` | Placa de 20 cm con materiales reales, isotermas | Placa de (madera…cobre), Aceleración temporal, Bordes, Clic (inyectar, enfriar, fuente, pintar material) | cm desde el centro, ±10 · inyecta calor |
| `schrodinger` | Paquete gaussiano: \|ψ\|² como altura y fase como color; túnel | Potencial (libre, barrera, doble rendija, pozo, oscilador), Altura V₀, Anchura de la barrera, Momento k₀, Anchura σ, Posición inicial x₀, Lanzar paquete | ±10 · pinta barrera |
| `raices` | Bisección, Newton, secante y punto fijo sobre f(x) | Método, f(x) =, g(x) =, a, b, x₀, x₁, Paso, Resolver | x (eje de la gráfica) |
| `sistemas` | 3 planos: Jacobi y Gauss-Seidel, residuo, radio espectral | Ejemplo, A11…A33, b1…b3, Iteraciones, Animar iteraciones | (x, y) del plano z = 0 · punto de partida |
| `optimizacion` | Gradiente con momento y Newton sobre z = f(x, y) | Función (Rosenbrock, Himmelblau…), f(x, y) =, Paso α, Momento β, Iteraciones máx. | región del dominio · punto inicial |
| `interpolacion` | Spline cúbico 3D; mínimos cuadrados con R² | Modo, Punto (añadir/quitar), Modelo, Ruido σ, Número de datos | espacio 3D |
| `integracion` | ∬ f dA con punto medio, trapecio y Simpson; orden observado | Función, f(x, y) =, Prismas de la regla, Celdas por lado n | [−2, 2]² |
| `edp1d` | Calor 1D en espacio-tiempo: FTCS, implícito, Crank-Nicolson | r = αΔt/Δx², Condición inicial | (x, t); `lab_sample` lee los 3 métodos a la vez |
| `coloreado` | \|f(z)\| como altura, arg f como color; ceros y polos con su orden | Función, f(z) =, Altura, Región R, curvas de módulo y fase | z = x + iy |
| `conforme` | Rejilla z deformada por w = f(z); puntos críticos f′ = 0 | Mapeo, w = f(z) =, Rejilla de partida, Deformación z → w, Animar | z = x + iy |
| `fractales` | Mandelbrot y Julia en relieve | Iteraciones máximas, Relieve, c de Julia, Vista inicial | x + iy como c (Mandelbrot) y z₀ (Julia) · elige la c de Julia |
| `campo` | Flechas, líneas de corriente RK4, partículas, ∇·F, ∇×F, equilibrios | Campo, P, Q, R (x, y, z) =, Usar gradiente, φ =, y casillas de flechas, líneas, partículas, divergencia y rotacional | (x, y) en el plano z = c |
| `teoremas` | Gauss (flujo frente a ∭∇·F) y Stokes (circulación frente a ∬∇×F·n) | Teorema, Campo F, Radio, Centro x/y/z, Inclinación θ, Azimut φ | (x, y, 0) |

## Recetas

**Efecto túnel** (E ≈ k₀²/2 = 4.5 < V₀ = 5):

```bash
mf lab_open '{"modulo":"schrodinger"}'
mf lab_set_param '{"nombre":"Potencial","valor":"barrera"}'
mf lab_set_param '{"nombre":"Altura","valor":5}'
mf lab_set_param '{"nombre":"Anchura de la barrera","valor":0.4}'
mf lab_set_param '{"nombre":"Momento","valor":3}'
mf lab_set_param '{"nombre":"Lanzar paquete"}'
sleep 4; mf lab_get_state   # info → «máx. tras el lanzamiento T = 63.4 %»
```

Repite con una anchura de 1.0 (T ≈ 26 %): la transmisión cae de forma exponencial con
la anchura. Usa el máximo `T`, no la lectura instantánea: el paquete transmitido
acaba absorbido en el borde del dominio.

**Ceros y polos:**
1. `lab_open` coloreado.
2. `lab_set_param {"nombre":"f(z)","valor":"(z^2+1)/(z-2)^2"}`.
3. `info` lista los ceros y los polos con su orden (×2 = polo doble). También vienen
   en `puntos_criticos`, y `lab_control encuadrar` lleva la cámara a cada uno.

**Estabilidad de FTCS:**
1. `lab_open` edp1d.
2. Pon `r = αΔt/Δx²` a 0.4 y luego a 0.6.
3. `info` muestra el error de cada método y el factor |1 − 4r|: por encima de 1, el
   esquema explícito diverge.

**Newton frente a bisección:**
1. `lab_open` raices.
2. Cambia `Método`, pulsa `Resolver` y compara las iteraciones de la tabla de `info`
   (orden ≈ 2 frente a 1).

**Gauss:**
1. `lab_open` teoremas.
2. `Campo F` = `fuente radial`.
3. `info` compara ∯F·n dA con ∭∇·F dV = 4πR³.
4. Mueve `Centro x` para sacar la esfera del origen y comprueba que siguen iguales.
