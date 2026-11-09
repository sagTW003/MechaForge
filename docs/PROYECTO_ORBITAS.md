# Proyecto de métodos numéricos: el movimiento de los astros

Cinco preguntas sobre planetas y órbitas, cada una resuelta con métodos numéricos y simulada en
3D en MechaForge. Este documento sirve de base para el informe: para cada pregunta da el
planteamiento, el modelo matemático, los métodos, cómo reproducirlo en el simulador, los
resultados medidos y su validación frente a un valor real o exacto.

| # | Pregunta | Unidad del curso | Métodos |
|---|---|---|---|
| 1 | ¿Dónde se «estaciona» el telescopio James Webb? | Raíces de ecuaciones | Bisección, secante, Newton · RK4 |
| 2 | ¿Cómo encontró Gauss el asteroide Ceres? | Derivación numérica y EDO | Diferencias hacia adelante, hacia atrás, centradas y de 5 puntos · Euler, Heun, RK4 |
| 3 | ¿Cuándo estará Marte más cerca de la Tierra? | Interpolación | Kepler por Newton · Lagrange, diferencias divididas de Newton, Newton–Gregory |
| 4 | Si la Tierra se detuviera, ¿cuánto tardaría en caer al Sol? | Integración numérica | Rectángulos, punto medio, Gauss–Legendre, tanh-sinh · trapecio, Simpson 1/3 y 3/8 y Romberg con cambio de variable · RK4 |
| 5 | ¿Por qué gira la órbita de Mercurio? | Ecuaciones diferenciales | Euler, Heun, RK4 · mínimos cuadrados y extrapolación |

## Cómo usarlo

- **Abrir:** *∑ Laboratorio → Física clásica → Mecánica celeste*. El selector «Pregunta» cambia de
  escena; ▶ anima, ⏭ avanza un paso, Ctrl+Z deshace.
- **Información** (abajo a la izquierda), en tres partes:
  1. la **respuesta** a la pregunta según el método elegido;
  2. la tabla con lo que da cada método (en negrita, el elegido);
  3. la **interpretación**, que se escribe sola con los números de la simulación: por qué el
     método da ese resultado (su orden, su error) y qué significa físicamente la respuesta.
- **📐 Modelo:** qué es exacto, qué es aproximado y qué es solo ilustrativo.
- **💾 Exportar la tabla (CSV):** guarda `Documentos/MechaForge/orbitas_preguntaN.csv` con punto y
  coma y coma decimal (así lo abre Excel en español; en Python:
  `pandas.read_csv(ruta, sep=";", decimal=",")`).
- **El código:** los métodos están en `project/mathlab/solvers/Celeste.gd` (funciones puras,
  comentadas, una sección por pregunta) y la escena en `project/mathlab/modules/CelesteModule.gd`.
  Las pruebas `_t_celeste` de `project/tests/LabTests.gd` comprueban los resultados de este
  documento (`--headless --path project -- mflabtest`).
- **Capturas:** `-- mflabshot <ruta.png> celeste p1 [nave] t 8` (p1…p5).

**Unidades.** UA, días y masas solares: GM☉ = k², con la constante gaussiana k = 0,01720209895
UA^(3/2)/día. c = 173,1446 UA/día; 1 UA = 149 597 870,7 km. La pregunta 1 usa unidades
canónicas (distancia entre los dos cuerpos = 1, periodo = 2π).

---

## 1. ¿Dónde se «estaciona» el telescopio James Webb?

**Planteamiento.** El JWST no orbita la Tierra: está cerca del punto L2 del sistema Sol–Tierra,
donde la gravedad de los dos cuerpos y la fuerza centrífuga del marco que gira se equilibran. Los
puntos L1, L2 y L3 no tienen fórmula cerrada: son raíces de una ecuación no lineal.

**Modelo (problema restringido circular de tres cuerpos).** En el marco que gira con el Sol
(masa 1 − μ, en x = −μ) y la Tierra (μ, en x = 1 − μ), el potencial efectivo es

  Ω(x, y) = (x² + y²)/2 + (1 − μ)/r₁ + μ/r₂,

y sobre el eje (y = 0) los equilibrios cumplen

  f(x) = ∂Ω/∂x = x − (1 − μ)(x + μ)/|x + μ|³ − μ(x − 1 + μ)/|x − 1 + μ|³ = 0,

con f′(x) = 1 + 2(1 − μ)/|x + μ|³ + 2μ/|x − 1 + μ|³ > 0: entre dos singularidades f es creciente
y hay una sola raíz en cada tramo. μ = 3,0404·10⁻⁶ (Sol–Tierra+Luna), 0,01215 (Tierra–Luna),
9,539·10⁻⁴ (Sol–Júpiter). L4 y L5 son exactos (triángulos equiláteros).

**Métodos.**
- Intervalo inicial con el radio de Hill r_H = (μ/3)^(1/3): L2 ∈ [1 − μ + r_H/2, 1 − μ + 2r_H]
  (f cambia de signo allí); L3 ∈ [−1,5; −0,5].
- **Bisección:** mitad del intervalo y nos quedamos con el subintervalo donde f cambia de signo.
- **Secante:** xₖ₊₁ = xₖ − f(xₖ)(xₖ − xₖ₋₁)/(f(xₖ) − f(xₖ₋₁)), desde los extremos del intervalo.
- **Newton:** xₖ₊₁ = xₖ − f(xₖ)/f′(xₖ), desde el extremo lejano.
- Parada: |xₖ − xₖ₋₁| ≤ 10⁻¹⁵·máx(1, |xₖ|). Orden observado
  p ≈ ln(eₖ₊₁/eₖ)/ln(eₖ/eₖ₋₁) (en la bisección, la pendiente de ln eₖ₊₁ frente a ln eₖ).
- **Nave:** ẍ − 2ẏ = ∂Ω/∂x, ÿ + 2ẋ = ∂Ω/∂y con RK4 de paso fijo; la constante de Jacobi
  C = 2Ω − v² se conserva y mide el error del integrador.

**En MechaForge.** La superficie de abajo es Ω: pozos en los cuerpos, sillas en L1–L3. La curva
blanca vertical es f(x) (comprimida con atan): **cada raíz es donde la curva atraviesa el plano
de la órbita.** Cada método avanza en su carril con una iteración cada 0,55 s: el intervalo
naranja de la bisección, las dos rectas de la secante (rosa) y la tangente de Newton (cian).
Clic sobre el eje: Newton empieza ahí. «Soltar la nave» la deja en reposo desplazada unos km.

**Resultados (Sol–Tierra, L2).**

| Método | Iteraciones | Evaluaciones | p teórico | p observado | Error final |
|---|---|---|---|---|---|
| Bisección | 44 | 45 de f | 1 | 0,98 | < 10⁻¹⁵ |
| Secante | 10 | 12 de f | 1,618 | 1,61 | 4·10⁻¹⁶ |
| Newton | 8 | 16 (f y f′) | 2 | 2,01 | 4·10⁻¹⁶ |

| Sistema | L1 | L2 | L3 |
|---|---|---|---|
| Sol–Tierra | 1 497 617 km de la Tierra | **1 507 679 km** de la Tierra | 149 597 605 km del Sol |
| Tierra–Luna | 58 019 km de la Luna | 64 515 km de la Luna | 381 675 km de la Tierra |
| Sol–Júpiter | 51,9 millones de km de Júpiter | 54,3 millones de km | 778,0 millones de km del Sol |

**Validación.** La NASA sitúa al JWST en torno a L2, a unos 1,5 millones de km: coincide. La nave
soltada a 1000 km de L2 se aleja exponencialmente (equilibrio inestable: por eso el JWST corrige su
órbita); cerca de L4 de Júpiter oscila sin escapar (estable para μ < 0,0385; ahí están los
asteroides troyanos). La constante de Jacobi deriva ~10⁻¹³ con RK4.

**Para el análisis.** ¿Por qué la bisección necesita ~44 iteraciones aunque nunca falla? ¿Qué pasa
si Newton empieza al otro lado de la Tierra (clic): por qué salta a otra raíz? ¿Por qué Newton, con
16 evaluaciones, compite con la secante, que hace 12?

---

## 2. ¿Cómo encontró Gauss el asteroide Ceres?

**Planteamiento.** Piazzi descubrió Ceres el 1 de enero de 1801 y la siguió 41 días antes de
perderla tras el Sol. Con tan pocos datos nadie sabía dónde buscarla. Gauss calculó su órbita y
predijo dónde reaparecería: el 31 de diciembre de 1801 la encontraron a medio grado de su
predicción. La idea clave: **la posición y la velocidad en un instante determinan la órbita**. La
posición se observa; la velocidad no: hay que **derivarla numéricamente**. Después, la órbita se
obtiene **resolviendo la EDO** del movimiento.

**Modelo.** Observaciones diarias (tᵢ, xᵢ, yᵢ) de la posición heliocéntrica de Ceres con un error
gaussiano σ·r en cada coordenada. Movimiento: r̈ = −GM·r/r³ (problema de dos cuerpos). De la
posición y la velocidad salen el semieje por la vis-viva, 1/a = 2/r − v²/GM, y la excentricidad
por el momento angular L = x·v_y − y·v_x: p = L²/GM y e = √(1 − p/a).

**Métodos.**
- **Derivación numérica** de la velocidad en la observación central del arco (día 21), con paso h:
  - hacia adelante: v ≈ (x(t + h) − x(t))/h, error O(h);
  - hacia atrás: v ≈ (x(t) − x(t − h))/h, error O(h);
  - centrada de 3 puntos: v ≈ (x(t + h) − x(t − h))/(2h), error O(h²);
  - centrada de 5 puntos: v ≈ (x(t − 2h) − 8x(t − h) + 8x(t + h) − x(t + 2h))/(12h), error O(h⁴).
- **Equilibrio truncamiento–ruido:** el error de truncamiento crece con h (∝ hᵖ), pero el ruido de
  las posiciones se amplifica al restar dos valores casi iguales y dividir entre h (∝ σ/h). Hay un
  h óptimo; el simulador lo busca probando h = 1, 2, … días.
- **EDO:** desde ese estado (posición observada + velocidad derivada) se integra la órbita hasta
  el día de la reaparición (343 días después) con **Euler** (orden 1), **Heun** o Euler mejorado
  (predictor de Euler y corrector con la media de las pendientes, orden 2) o **Runge–Kutta 4**
  (orden 4). El último paso se acorta para terminar justo en el día pedido.

**En MechaForge.** La órbita real de Ceres es la discontinua; el arco cian es lo observado; las
bolas son las observaciones y las grandes, las que usa la fórmula elegida. En el día 21 salen las
flechas: la blanca es la velocidad real y las de color, la de cada fórmula, con su error aumentado
(×10, ×100… según haga falta). Desde ahí, cada fórmula tiene su órbita integrada por la EDO, con
los pasos marcados como puntos, hasta el día de la reaparición, donde se ven la predicción y la
posición real unidas por una línea roja. La Tierra y Ceres se mueven con la fecha, y la línea tenue
entre ellas es la visual de Piazzi. Controles: fórmula, h, integrador y paso de la EDO, arco,
error de cada posición, días hasta la reaparición y 🎲 otra semilla.

**Resultados.**

*Sin error en las observaciones* (orden puro de cada fórmula), error al reaparecer:

| Fórmula | h = 1 día | h = 5 días | h = 10 días | Error de v con h = 5 |
|---|---|---|---|---|
| Hacia adelante, O(h) | 0,20° | 1,01° | 2,04° | 1 % |
| Hacia atrás, O(h) | 0,20° | 0,99° | 1,96° | 1 % |
| Centrada 3 puntos, O(h²) | 0,000° | 0,002° | 0,010° | 0,007 % |
| Centrada 5 puntos, O(h⁴) | 0,000° | 0,000° | 0,000° | 9·10⁻⁷ % |

El error de la velocidad confirma los órdenes: al duplicar h se duplica con la fórmula hacia
adelante (orden 1,00) y se cuadruplica con la centrada (orden 2,00).

*Con un error de 0,01 % en cada posición* (≈ 40 000 km, como la precisión de la época):

| Fórmula | h = 1 | h = 5 | h = 10 | h = 20 |
|---|---|---|---|---|
| Hacia adelante | 1,47° | 0,99° | 1,86° | 4,11° |
| Centrada 3 puntos | 0,63° | 0,47° | **0,028°** | 0,006° |
| Centrada 5 puntos | 0,59° | 0,62° | 0,040° | — (faltan datos) |

Con h pequeño domina el ruido; con h grande, el truncamiento (en las de orden 1). Con 0,1 % de
error, el h óptimo de la centrada es ≈ 10 días (0,19°): por encima vuelve a crecer.

*La EDO por sí sola* (con la velocidad exacta, 343 días), error en la posición:

| Integrador | h = 5 días | h = 1 día | Orden observado |
|---|---|---|---|
| Euler | 0,62° | 0,13° | 0,99 |
| Heun | 0,011° | 0,0004° | 2,00 |
| RK4 | < 10⁻⁶° | < 10⁻⁶° | 4,01 |

**Respuesta (centrada, h = 10 días, RK4 con paso 1 día, error 0,01 %).** El día 21 Ceres va a
18,9 km/s; la órbita da a = 2,7650 UA (real 2,7675) y e = 0,078 (real 0,0785). La predicción para
el 31 de diciembre de 1801 cae a **0,028°** de la posición real (unos 400 000 km).

**Validación.** Sin ruido, la centrada de 5 puntos y RK4 reproducen la órbita real a menos de una
millonésima de grado; los órdenes observados de las fórmulas (1, 2, 4) y de los integradores (1,
2, 4) coinciden con la teoría.

**Para el análisis.** ¿Por qué la fórmula de orden 4 no siempre gana con datos con ruido? ¿Cómo
se elige h? ¿Qué aporta más error a la predicción: la derivada o la EDO?

---

## 3. ¿Cuándo estará Marte más cerca de la Tierra?

**Planteamiento.** Cada ~26 meses Marte se acerca a la Tierra. Los anuarios astronómicos dan
posiciones cada cierto número de días; ¿con qué precisión se puede sacar de esa tabla el instante
y la distancia del acercamiento?

**Modelo.** Posiciones heliocéntricas de la Tierra y Marte con los elementos keplerianos medios de
JPL (E. M. Standish, válidos de 1800 a 2050): a, e, I, L, ϖ, Ω con su ritmo por siglo. Anomalía
media M = L − ϖ, **ecuación de Kepler E − e sen E = M por Newton** (unas 3 iteraciones), posición
en el plano de la órbita y tres rotaciones a la eclíptica. La función es
d(t) = |r_Marte(t) − r_Tierra(t)|.

**Métodos.**
- La tabla (efeméride): d(t) cada Δ días desde el día 1 de un mes (los nodos no caen en el mínimo).
- Un polinomio interpolante por los nodos centrados en el menor valor de la tabla:
  - **Lagrange, grado 2 (3 nodos):** p(t) = Σⱼ yⱼ·ℓⱼ(t), con ℓⱼ(t) = Πₘ≠ⱼ (t − tₘ)/(tⱼ − tₘ);
  - **Newton en diferencias divididas, grado 4 (5 nodos):** p(t) = f[t₀] + f[t₀,t₁](t − t₀) + …,
    evaluado por Horner;
  - **Newton–Gregory hacia adelante, grado 6 (7 nodos):** con s = (t − t₀)/Δ,
    p = y₀ + sΔy₀ + s(s − 1)/2!·Δ²y₀ + … (diferencias finitas, para nodos equiespaciados).
- El mínimo del polinomio, por **sección áurea** entre los nodos vecinos del menor valor.
- **Referencia sin tabla:** sección áurea sobre d(t) evaluada directamente (tolerancia 10⁻⁶ días).

Con los mismos nodos, los tres métodos darían el mismo polinomio (es único); aquí se comparan con
3, 5 y 7 nodos para ver el efecto del grado. Los nodos van centrados: con un número par de nodos
el polinomio queda torcido hacia un lado y su mínimo se desplaza.

**En MechaForge.** La Tierra y Marte se mueven fecha a fecha, unidos por una línea con la
distancia. Los puntos y las líneas tenues sobre las órbitas son la tabla: la Tierra y Marte en cada
fecha de la tabla. Detrás, un tablero con d(t): la curva real (blanca), los nodos, el polinomio de
cada método (con sus nodos marcados en su color bajo el eje) y el mínimo de cada uno con su error
en horas; el cursor amarillo es la fecha de la animación.

**Resultados** (error del instante del mínimo; entre paréntesis, de la distancia).

| Acercamiento | Δ | Lagrange (grado 2) | Newton (grado 4) | Newton–Gregory (grado 6) |
|---|---|---|---|---|
| 2025 | 10 días | −1,46 h | −0,11 h | −0,02 h |
| 2025 | 20 días | −1,07 h (19 025 km) | +0,31 h (10 365 km) | +0,25 h (5 994 km) |
| 2025 | 40 días | −40,1 h | −19,6 h | −14,2 h |
| 2027 | 10 días | −0,10 h | −0,02 h | −0,01 h |
| 2027 | 20 días | −0,45 h (3 911 km) | −0,27 h (1 327 km) | −0,18 h (751 km) |
| 2027 | 40 días | +12,6 h | +6,6 h | +5,2 h |

Referencia (sección áurea sobre la efeméride): 12 ene 2025 14:07 UT a 96 085 787 km y 20 feb 2027
00:25 UT a 101 403 300 km.

**Validación.** NASA: 12 de enero de 2025 a 96,08 millones de km y 20 de febrero de 2027 (00:07 UT)
a 101,41 millones de km. La referencia cae el mismo día, a menos de 0,01 millones de km.

**Para el análisis.** ¿Por qué el error baja al subir el grado (∝ Δ^(n+1)·d^(n+1))? ¿Por qué con
Δ = 40 días ningún grado alcanza? Ventajas de Newton y Newton–Gregory frente a Lagrange cuando se
añade un nodo.

---

## 4. Si la Tierra se detuviera, ¿cuánto tardaría en caer al Sol?

**Planteamiento.** Si la Tierra dejara de orbitar, caería en línea recta. La energía da la
velocidad en cada r y el tiempo es una integral… con el integrando infinito en el punto de partida.

**Modelo.** Desde el reposo en r = R: v²/2 − GM/r = −GM/R, así que

  t = ∫₀ᴿ dr / √(2GM(1/r − 1/R)).

El integrando diverge como 1/√(R − r) en r = R: **integral impropia**, aunque convergente. Valor
exacto: t = (π/2)·R^(3/2)/√(2GM) = T/(4√2) = **64,5689 días**, con T el año.

**Métodos.** Ninguno evalúa f(R) = ∞ (el trapecio y Simpson directos no se pueden usar).
- Sobre dt/dr, que se dispara junto a R:
  - **rectángulos por la izquierda** y **punto medio:** error ∝ n^(−1/2) por la singularidad;
  - **Gauss–Legendre** (n puntos): error ∝ n^(−1);
  - **tanh-sinh** (doble exponencial): amontona los nodos junto a los extremos con pesos que caen
    más rápido que crece f, y converge muy rápido. Se integra en w = R − r para no perder por
    redondeo los nodos muy cercanos a R.
- Con el **cambio de variable r = R sen²u**, el integrando pasa a ser 2R^(3/2) sen²u/√(2GM) en
  u ∈ [0, π/2], suave y periódico. Sobre él: **trapecio**, **Simpson 1/3**, **Simpson 3/8** y
  **Romberg** (trapecios con extrapolación de Richardson).
- **EDO:** r̈ = −GM/r² con RK4 hasta la superficie del Sol; el instante del choque se interpola
  linealmente dentro del último paso.

**En MechaForge.** La Tierra cae por el eje; un fantasma sigue en la órbita normal. Sobre el camino,
la curva blanca es el integrando dt/dr y **cada barra es un nodo de la cuadratura elegida** (su
alto, el valor de f). Con el cambio de variable aparece la curva verde, ya suave, con sus nodos.

**Resultados.**

| Método (n = 16) | Resultado (días) | Error | Evaluaciones |
|---|---|---|---|
| Rectángulos por la izquierda | 49,494 | 15 | 16 |
| Punto medio | 58,372 | 6,2 | 16 |
| Gauss–Legendre | 62,400 | 2,2 | 16 |
| Tanh-sinh | 64,5689074 | 1,4·10⁻¹⁴ | 29 |
| Trapecio con r = R sen²u | 64,5689074 | < 10⁻¹³ | 17 |
| Simpson 1/3 con r = R sen²u | 64,5689074 | < 10⁻¹³ | 17 |
| Simpson 3/8 con r = R sen²u | 64,5689074 | 1,4·10⁻¹⁴ | 19 |
| Romberg con r = R sen²u | 64,5689074 | 1,4·10⁻¹⁴ | 17 |

Convergencia (error para n = 4, 8, 16, 32, 64): rectángulos 31; 21; 15; 11; 7,5 (p = 0,50); punto
medio 12; 8,7; 6,2; 4,4; 3,1 (p = 0,50); Gauss–Legendre 7,9; 4,2; 2,2; 1,1; 0,55 (p = 0,99). Para
4 cifras correctas el punto medio necesitaría unos 25 millones de puntos y Gauss unos 7 000; con el
cambio de variable bastan 3.

EDO con RK4 hasta la superficie del Sol (exacto 64,5602 días): h = 0,1 d → 64,5409;
h = 0,01 d → 64,56015; h = 0,001 d → 64,56020. Llega a ~616 km/s.

**Validación.** Fórmula cerrada T/(4√2) y la del tiempo hasta un radio r,
t(r) = √(R³/2GM)(√(x(1 − x)) + arccos √x), x = r/R. La Tierra tarda 53 días en la primera mitad
del camino y 12 en la segunda.

**Para el análisis.** ¿Por qué el orden de punto medio es ½ y no 2? ¿Qué hace el cambio de
variable con la singularidad? ¿Por qué el trapecio es exacto sobre sen²u en [0, π/2]?

---

## 5. ¿Por qué gira la órbita de Mercurio?

**Planteamiento.** El perihelio de Mercurio avanza 574″ por siglo; la gravedad de los demás
planetas explica 532″. Los 43″ restantes fueron un misterio hasta que Einstein (1915) los dedujo
de la relatividad general. ¿Puede una simulación numérica medir un efecto tan pequeño?

**Modelo.** Corrección de Schwarzschild a primer orden para una partícula de prueba:

  r̈ = −GM·r/r³·(1 + 3λL²/(c²r²)),

con L = |r × v| (constante, la fuerza es central) y λ = 1 en la realidad. Predicción:
Δϖ = 6πGM/(c²a(1 − e²)) por vuelta = **42,98″ por siglo** (a = 0,387098 UA, e = 0,205630).

**Métodos.**
- **Integradores:** Euler explícito (orden 1), **Heun** o Euler mejorado (orden 2: predictor de
  Euler y corrector con la media de las pendientes) y Runge–Kutta 4 (orden 4).
- **Perihelios:** cuando rₖ₋₁ > rₖ ≤ rₖ₊₁, el vértice de la parábola por los tres pasos da el
  instante τ, y el ángulo se interpola en τ con la parábola de Lagrange por θₖ₋₁, θₖ, θₖ₊₁.
- **Precesión medida:** pendiente de la recta de mínimos cuadrados de la longitud del perihelio
  ϖ(t), en ″ por siglo.
- **Extrapolación:** 43″/siglo son 5·10⁻⁷ rad por vuelta, del orden del propio error del
  integrador. Se exagera λ (0, 10⁴, …, 4·10⁴), se mide P(λ) y se ajusta por mínimos cuadrados
  P(λ) ≈ c₀ + c₁λ + c₂λ² (ecuaciones normales 3×3 por Cholesky). **c₁ es la predicción para λ = 1**;
  c₀ es la precesión que inventa el integrador (se descuenta sola) y c₂ la no linealidad de
  exagerar tanto. Con una recta (sin c₂) el resultado queda sesgado.

**En MechaForge.** Los tres integradores a la vez: Euler (rojo) se abre en espiral y escapa; Heun
(amarillo) y RK4 (cian) siguen la elipse que gira (en la escena λ = 10⁵: 2,9° por vuelta). Cada
perihelio deja una marca y una línea al Sol: la roseta. Arriba, el tablero con P(λ) medido y la
parábola ajustada. La animación integra las mismas vueltas que se miden y se detiene al
completarlas («⟲ Repetir las vueltas» la reinicia). «📐 Medir y extrapolar a λ = 1» repite la
medida con el paso y las vueltas elegidos.

**Resultados (5 vueltas por λ).**

| Integrador | h | Deriva de energía | Precesión numérica (c₀) | c₁ (parábola) | Recta (sesgada) |
|---|---|---|---|---|---|
| Euler | 0,1 d | 0,26 | 653 464″ | 24,2″ | 24,4″ |
| Heun | 0,1 d | 4,9·10⁻⁵ | −31 562″ | **42,94″** | 43,55″ |
| RK4 | 0,1 d | 1,1·10⁻¹⁰ | 4,7″ | **42,978″** | 43,583″ |
| Euler | 0,25 d | 0,43 | 1 485 839″ | 12,7″ | 12,8″ |
| Heun | 0,25 d | 3,9·10⁻⁴ | −196 734″ | 42,75″ | 43,35″ |
| RK4 | 0,25 d | 7,2·10⁻⁹ | 12″ | 42,978″ | 43,582″ |

Con pasos mayores: Heun da 42,02″ (h = 0,5) y 39,52″ (h = 1); RK4, 42,977″ y 42,85″.

**Validación.** Relatividad general: 42,98″ por siglo; observado (descontados los planetas):
42,98 ± 0,04″.

**Para el análisis.** ¿Por qué Euler no sirve aunque el ajuste descuente c₀? ¿Cuánto hay que
bajar h para que Heun alcance a RK4, y cuánto cuesta? ¿Por qué el ajuste lineal da 43,58″ y el
cuadrático 42,98″?

---

## Límites del modelo

Están declarados en el panel 📐 Modelo de la aplicación:

- **Pregunta 1:** problema restringido y circular: los dos cuerpos giran en círculos y la nave no
  los perturba.
- **Pregunta 2:** simplificación del problema de Gauss. Se observan posiciones heliocéntricas
  (x, y) una vez al día en el plano de la eclíptica, y la órbita se integra sin la atracción de
  Júpiter. Gauss solo tenía ángulos medidos desde la Tierra, y Ceres está inclinada 10,6°.
- **Pregunta 3:** elementos medios de JPL, sin perturbaciones entre planetas. Dan errores de
  minutos de arco, así que el instante del mínimo sale a horas del publicado.
- **Pregunta 4:** la Tierra se trata como una partícula y el Sol como fijo.
- **Pregunta 5:** solo la corrección relativista a primer orden, sin los demás planetas.
- **Escena:** los tamaños del Sol y los planetas no están a escala; las órbitas y las distancias
  sí.

## Referencias

- C. D. Murray y S. F. Dermott, *Solar System Dynamics*, Cambridge, 1999 (cap. 3, puntos de Lagrange).
- NASA, *Webb Orbit*: el JWST orbita en torno a L2, a unos 1,5 millones de km de la Tierra.
- C. F. Gauss, *Theoria motus corporum coelestium*, 1809; D. Teets y K. Whitehead, «The Discovery
  of Ceres: How Gauss Became Famous», *Mathematics Magazine* 72 (1999).
- E. M. Standish, *Keplerian Elements for Approximate Positions of the Major Planets*, JPL
  (ssd.jpl.nasa.gov/planets/approx_pos.html).
- EarthSky, *Mars closest to Earth* (acercamientos de 2025 y 2027).
- J. M. A. Danby, *Fundamentals of Celestial Mechanics*, Willmann-Bell, 1988.
- H. Takahasi y M. Mori, «Double exponential formulas for numerical integration», *Publ. RIMS* 9 (1974).
- A. Einstein, «Erklärung der Perihelbewegung des Merkur aus der allgemeinen
  Relativitätstheorie», 1915; S. Weinberg, *Gravitation and Cosmology*, §8.6.
- R. L. Burden y J. D. Faires, *Análisis numérico* (raíces, derivación, interpolación, cuadratura, EDO).
