---
name: mechaforge-laboratorio
description: Usar el Laboratorio matemático 3D de MechaForge desde OpenClaw — graficar funciones, curvas, superficies y datos (lab_plot, también lo que venga en una imagen o un PDF), abrir módulos (ondas, calor, Schrödinger, ecuaciones no lineales con 15 métodos, sistemas lineales y no lineales, optimización, interpolación 1D y 3D, integración y derivación numéricas (18 cuadraturas y 14 derivadas), integral doble, EDP numérica, coloreado de dominio, mapeos conformes, fractales, campos vectoriales, Gauss/Stokes), cambiar funciones y parámetros, comparar métodos, leer resultados y explicar la matemática con datos.
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
| `lab_list_modules` | — | Los 18 módulos: `id`, pilar, nombre y descripción |
| `lab_plot` | ver abajo | Dibuja en el módulo `graficas` (lo abre si hace falta) y devuelve `marcas` (raíces, extremos, cortes) e `info`. Es lo más rápido para «grafica esto» |
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
| `expresion` | La fórmula; si no es válida devuelve el error del analizador. Los campos opcionales (f₂…f₄ de Gráficas) aceptan `""` para vaciarlos |
| `texto` | Texto libre, p. ej. los puntos `"(0, 1); (2, 3.5)"` |
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

## Seguimiento de manos (lo maneja el humano)

El laboratorio también se controla con las manos delante de la webcam: botón
«🖐 Manos» o tecla H. **Tú no puedes activarlo**: la API no enciende la cámara. Si el
humano pregunta cómo funciona, explícale los gestos:

| Gesto | Acción |
|---|---|
| ☝ Índice extendido | Mueve el cursor y muestra el tooltip |
| 🤏 Pellizco pulgar–índice | Gira la gráfica 3D o desplaza la 2D; sobre un deslizador, ajuste fino; sobre un botón, clic |
| 🤏🤏 Pellizco con las dos manos | Zoom: separarlas acerca la cámara |
| ✊✊ Las dos manos en puño | Agarra la escena en 3D como un objeto: se desplaza con las manos, empujar hacia la pantalla la aleja (tirar la acerca), adelantar una mano y retrasar la otra la gira, doblar las muñecas la inclina |
| 🖐 Palma abierta | Pausa; mantenida 1 s, reinicia la vista |

Detalles del pellizco:
- se activa a 3 cm y se suelta a 4,5 cm (histéresis);
- junto al cursor, un medidor muestra la distancia y la fase: acercando, activo o
  soltando;
- con precisión adaptativa, los movimientos lentos son finos (×0.35) y los rápidos
  van 1:1;
- modo puño: mientras una mano está en puño, sus pellizcos no cuentan hasta que se
  abre (apuntar o palma);
- con la mano lejos, los umbrales crecen solos. Si aun así no detecta el pellizco,
  sugiere «Compensación con la mano lejos» o «Cámara en 1280×720» en el panel.

Todo se ajusta en el panel «✋ Seguimiento de manos». Guía completa:
`docs/SEGUIMIENTO_MANOS.md` del repositorio.

## Expresiones

Se escriben como en papel:
- multiplicación implícita (`2x`, `3(x+1)`, `2πx`, `x|x|`);
- potencias con `^`, `**` o superíndices (`x²`, `e⁻ˣ`); `e^x` equivale a `exp(x)`;
- funciones sin paréntesis: `sin x`, `sin 2x` (= sin(2x)), `sin x cos x`, `sin^2 x`,
  `sin^-1 x` (= asin x);
- nombres en español: `sen`, `tg`, `arcsen`, `arctg`, `senh`, `raíz`, `sgn`;
- `√x`, `∛x`, `|x|`, `log_2 x`, `½`, coma decimal (`0,5x`);
- palabras pegadas (`sinx` → sin x) y paréntesis que faltan al final se corrigen solos;
- constantes `pi`/`π`, `e`, `tau`, `inf`/`∞` (en los límites de integración) e `i`
  (unidad imaginaria en modo complejo).

Si una expresión no es válida, el error sugiere el nombre correcto («¿Quisiste decir
«sin»?»). Si la envías con `lab_set_param`, puedes usar cualquiera de estas formas.

Funciones:
- reales: `sin cos tan asin acos atan atan2 sinh cosh tanh asinh acosh atanh exp log ln
  log10 sqrt cbrt abs floor ceil sign min max pow mod sec csc cot` (log = ln);
- complejas: `sin cos tan sinh cosh tanh exp log sqrt abs conj re im arg pow`.

Las fórmulas se compilan a GLSL y se evalúan en la GPU.

## Módulos

| id | Qué muestra | Controles clave | Coordenadas `x, y` · Perturbar |
|---|---|---|---|
| `onda` | Membrana ∂²u/∂t² = c²∇²u (FDTD), energía, modos normales | Membrana, Frontera (fija/libre/absorbente), Velocidad de onda c, Amortiguamiento, Interferencia (2 fuentes), m, n, Excitar el modo | [−1, 1]² · pulso gaussiano |
| `calor` | Placa de 20 cm con materiales reales, isotermas | Placa de (madera…cobre), Aceleración temporal, Bordes, Clic (inyectar, enfriar, fuente, pintar material) | cm desde el centro, ±10 · inyecta calor |
| `schrodinger` | Paquete gaussiano: \|ψ\|² como altura y fase como color; túnel | Potencial (libre, barrera, doble rendija, pozo, oscilador), Altura V₀, Anchura de la barrera, Momento k₀, Anchura σ, Posición inicial x₀, Lanzar paquete | ±10 · pinta barrera |
| `graficas` | Calculadora gráfica: hasta 4 funciones y = f(x) con raíces, extremos y cortes marcados; paramétricas, polares r(θ), superficies z = f(x, y) y puntos de datos | Tipo, Ejemplo, f₁(x) = … f₄(x) =, x mín./máx., y automática, y mín./máx., Marcar raíces…, x(t) =, y(t) =, r(t) = (t es θ), f(x, y) =, Puntos (x, y) | (x, y) del tablero · añade un punto |
| `raices` | 15 métodos para f(x) = 0 (intervalo, con derivadas, sin derivadas, punto fijo) con tabla, orden observado y comparación | Ejemplo (9 funciones), Método, f(x) =, g(x) =, a, b, x₀, x₁, Tolerancia 10ᵏ, Paso, Resolver, Comparar todos los métodos | x (eje de la gráfica) |
| `sistemas` | 3 planos: Jacobi, Gauss-Seidel, SOR, Richardson, descenso, gradiente conjugado; eliminación geométrica, LU, Cholesky, QR, Cramer | Ejemplo, A11…A33, b1…b3, Iteraciones, casillas de cada método, ω de SOR, ω óptimo, Método directo, Paso de eliminación (0–5) | (x, y) del plano z = 0 · punto de partida |
| `nolineal` | F(x, y) = 0: curvas f₁ = 0 y f₂ = 0, 7 métodos y cuencas de atracción de Newton | Ejemplo, f₁, f₂, g₁, g₂ (x, y) =, Región R, x₀, y₀, Iteraciones máx., casillas de cada método, Cuencas | (x, y) del plano · punto de partida |
| `optimizacion` | Gradiente con momento y Newton sobre z = f(x, y) | Función (Rosenbrock, Himmelblau…), f(x, y) =, Paso α, Momento β, Iteraciones máx. | región del dominio · punto inicial |
| `interpolacion` | Spline 3D, Catmull-Rom, B-spline, Bézier; mínimos cuadrados con R²; superficies por datos dispersos (IDW, RBF, Delaunay) | Modo, casillas de curvas, Punto (añadir/quitar), Modelo, Ruido σ, Método, Número de puntos, Potencia p, Forma ε | espacio 3D · añade un dato |
| `interp1d` | 13 métodos de interpolación sobre la misma función y nodos; error ‖f − p‖∞, constante de Lebesgue | Función (Runge, |x|, eˣ… o Datos libres), f(x) =, intervalo a/b, Nodos (equiespaciados, Chebyshev…), Número de nodos n, x*, casillas de cada método, Grado m | (x, y) de la gráfica · x* o arrastra un nodo |
| `integracion` | **Integración y derivación 2D.** Modo integración: ∬_R f dA en R: a ≤ x ≤ b, c(x) ≤ y ≤ d(x) con 19 métodos (producto compuestas, Romberg, Gauss–Legendre/Lobatto p × p, Clenshaw–Curtis, cubatura de 7 puntos, iteradas adaptativas Gauss–Kronrod/Simpson/tanh-sinh, Genz–Malik, Monte Carlo, estratificado, Halton, Fibonacci); `info` da valor, error, evaluaciones y orden observado. Modo derivación: ∂f/∂x, ∂f/∂y, ∂²f/∂x², ∂²f/∂y², ∂²f/∂x∂y, laplaciano, \|∇f\| y D_u f en P con 11 métodos, error frente a h y hessiana | Modo, Ejemplo, f(x, y) =, a =, b =, c(x) =, d(x) = (expresiones en x), Método, n (subintervalos por lado), Nodos de Gauss p, Tolerancia 10ᵏ, Muestras N = 10ᵏ · Derivada, x₀ =, y₀ =, Dirección θ de D_u f (°), Paso h = 10ᵏ, Niveles de Richardson, Ruido en f, x mín. =, x máx. =, y mín. =, y máx. = · Comparar todos los métodos | (x, y) de la región o de la ventana · integración: sube n; derivación: elige P |
| `calculo` | Integración 1D con 18 cuadraturas o derivación con 14 métodos (1.ª y 2.ª derivada) sobre la misma f(x); tabla con valor, error, evaluaciones y orden observado; gráfica del error (frente a evaluaciones o frente a h) | Modo (Integración / Derivación), Ejemplo, f(x) =, a =, b = (admiten `pi`, `inf`, `-inf`), Método, n, Tolerancia 10ᵏ, Muestras N = 10ᵏ · Derivada, x₀ =, Paso h = 10ᵏ, Ruido en f, N de Chebyshev · Comparar todos los métodos | x de la gráfica · mueve a o b (integración) o x₀ (derivación) |
| `edp1d` | Calor 1D en espacio-tiempo: FTCS, implícito, Crank-Nicolson | r = αΔt/Δx², Condición inicial | (x, t); `lab_sample` lee los 3 métodos a la vez |
| `coloreado` | \|f(z)\| como altura, arg f como color; ceros y polos con su orden | Función, f(z) =, Altura, Región R, curvas de módulo y fase | z = x + iy |
| `conforme` | Rejilla z deformada por w = f(z); puntos críticos f′ = 0 | Mapeo, w = f(z) =, Rejilla de partida, Deformación z → w, Animar | z = x + iy |
| `fractales` | Mandelbrot y Julia en relieve | Iteraciones máximas, Relieve, c de Julia, Vista inicial | x + iy como c (Mandelbrot) y z₀ (Julia) · elige la c de Julia |
| `campo` | Flechas, líneas de corriente RK4, partículas, ∇·F, ∇×F, equilibrios | Campo, P, Q, R (x, y, z) =, Usar gradiente, φ =, y casillas de flechas, líneas, partículas, divergencia y rotacional | (x, y) en el plano z = c |
| `teoremas` | Gauss (flujo frente a ∭∇·F) y Stokes (circulación frente a ∬∇×F·n) | Teorema, Campo F, Radio, Centro x/y/z, Inclinación θ, Azimut φ | (x, y, 0) |

## Recetas

**Integral doble en una región curva y derivadas parciales:**

```bash
mf lab_open '{"modulo":"integracion"}'
mf lab_set_param '{"nombre":"Ejemplo","valor":"disco"}'          # o a, b, c(x), d(x) a mano
mf lab_set_param '{"nombre":"Método","valor":"Genz"}'
mf lab_set_param '{"nombre":"Comparar todos","valor":true}'      # info: tabla de los 19 métodos
mf lab_set_param '{"nombre":"Modo","valor":"Derivación"}'
mf lab_set_param '{"nombre":"Derivada","valor":"mixta"}'         # ∂²f/∂x∂y
mf lab_perturb '{"x":0.5,"y":0.3}'                              # mueve P
```

**Graficar (también lo que pida una imagen o un PDF):** `lab_plot` lo hace en una
sola llamada. Si el humano adjuntó un archivo en el chat de MechaForge, su texto te
llega entre `<<<DOCUMENTO …>>>` y, si tu modelo tiene visión, las imágenes y las
primeras páginas; la ruta de una copia local también va en el mensaje (útil con tu
herramienta `pdf` o `image`).

```bash
mf lab_plot '{"funciones":["x^2 - 2","sin x"],"x":[-3,3],"titulo":"Ejercicio 3"}'
mf lab_plot '{"parametrica":{"x":"cos(3t)","y":"sin(2t)","t":[0,"2pi"]}}'
mf lab_plot '{"polar":{"r":"1 + cos θ","t":[0,"2pi"]}}'
mf lab_plot '{"superficie":"sin x cos y","x":[-3,3],"y":[-3,3]}'
mf lab_plot '{"funciones":["0.5x + 1"],"x":[0,6],"puntos":[[1,1.4],[2,2.1],[3,2.4]]}'
```

La respuesta trae `marcas` («Raíz de f₁: x = 1.4142», «Mínimo de f₁: (0, -2)»,
«Corte f₁ = f₂: …»): úsalas para contestar con números. `"y"` es opcional (escala
automática que ignora las asíntotas); lo que no se entiende se omite y llega en
`errores`.

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

**Comparar métodos para f(x) = 0:**
1. `lab_open` raices.
2. Elige un `Ejemplo`, por ejemplo `raíz triple` o `arctan`.
3. `lab_set_param {"nombre":"Comparar todos","valor":true}`.
4. `info` lista los 15 métodos con iteraciones, evaluaciones, orden teórico y
   observado, y la raíz a la que llega cada uno. Con la raíz triple, Newton se vuelve
   lineal y «Newton para raíces múltiples» no.

**Fenómeno de Runge:**
1. `lab_open` interp1d.
2. `Número de nodos n` = 15.
3. Compara `Nodos` = `equiespaciados` con `Chebyshev`: `info` da ‖f − p‖∞ de cada
   método y la constante de Lebesgue (≈ 30 frente a ≈ 2.5 con 11 nodos).

**Sistemas no lineales:**
1. `lab_open` nolineal.
2. `Ejemplo` = `z³ = 1`.
3. `lab_perturb {"x":…, "y":…}` cambia el punto de partida.
4. `info` dice a qué solución llega cada método y en cuántas iteraciones. `lab_sample`
   en un punto dice a qué solución lleva Newton desde ahí (cuencas fractales).

**Gauss:**
1. `lab_open` teoremas.
2. `Campo F` = `fuente radial`.
3. `info` compara ∯F·n dA con ∭∇·F dV = 4πR³.
4. Mueve `Centro x` para sacar la esfera del origen y comprueba que siguen iguales.
