# Proyecto de métodos numéricos: el movimiento de los astros

Cinco preguntas sobre planetas y órbitas, cada una resuelta con un método numérico y simulada en
3D en MechaForge. Este documento sirve de base para el informe: para cada pregunta da el
planteamiento, el modelo matemático, el método, cómo reproducirlo en el simulador, los resultados
medidos y su validación frente a un valor real o exacto.

| # | Pregunta | Unidad del curso | Métodos |
|---|---|---|---|
| 1 | ¿Dónde se «estaciona» el telescopio James Webb? | Raíces de ecuaciones | Bisección, secante, Newton · RK4 |
| 2 | ¿Cómo encontró Gauss el asteroide Ceres? | Sistemas lineales y mínimos cuadrados | Ecuaciones normales + Cholesky, QR |
| 3 | ¿Cuándo estará Marte más cerca de la Tierra? | Interpolación | Kepler por Newton, lineal, Lagrange cuadrática, spline cúbico |
| 4 | Si la Tierra se detuviera, ¿cuánto tardaría en caer al Sol? | Integración numérica | Trapecio, Simpson, punto medio, Gauss–Legendre, tanh-sinh, cambio de variable · RK4 |
| 5 | ¿Por qué gira la órbita de Mercurio? | Ecuaciones diferenciales | Euler, RK4, Verlet · mínimos cuadrados y extrapolación |

## Cómo usarlo

- **Abrir:** *∑ Laboratorio → Física clásica → Mecánica celeste*. El selector «Pregunta» cambia de
  escena; ▶ anima, ⏭ avanza un paso, Ctrl+Z deshace.
- **Información (abajo a la izquierda):** la tabla de resultados de la pregunta. **📐 Modelo:**
  qué es exacto, qué es aproximado y qué es solo ilustrativo.
- **💾 Exportar la tabla (CSV):** guarda `Documentos/MechaForge/orbitas_preguntaN.csv` con punto y
  coma y coma decimal (así lo abre Excel en español; en Python:
  `pandas.read_csv(ruta, sep=";", decimal=",")`).
- **El código:** los métodos están en `project/mathlab/solvers/Celeste.gd` (funciones puras,
  comentadas, una sección por pregunta) y la escena en `project/mathlab/modules/CelesteModule.gd`.
  Las pruebas `_t_celeste` de `project/tests/LabTests.gd` comprueban cada resultado de este
  documento (`--headless --path project -- mflabtest`).
- **Capturas:** `-- mflabshot <ruta.png> celeste p1 [nave] t 8` (p1…p5).

**Unidades.** UA, días y masas solares: GM☉ = k², con la constante gaussiana k = 0,01720209895
UA^{3/2}/día. c = 173,1446 UA/día; 1 UA = 149 597 870,7 km. La pregunta 1 usa unidades canónicas
(distancia entre los dos cuerpos = 1, periodo = 2π).

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
- Intervalo inicial con el radio de Hill r_H = (μ/3)^{1/3}: L2 ∈ [1 − μ + r_H/2, 1 − μ + 2r_H]
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
perderla tras el Sol. Con tan pocos datos nadie sabía dónde buscarla. Gauss, con 24 años, inventó
el método de mínimos cuadrados, calculó la órbita y predijo dónde reaparecería: el 31 de diciembre
de 1801 la encontraron a medio grado de su predicción.

**Modelo.** Una órbita kepleriana con el Sol en un foco es una cónica: 1/r = A + B cos θ + C sen θ,
lineal en (A, B, C). Con N observaciones (rᵢ, θᵢ) hay N ecuaciones y 3 incógnitas: M·c ≈ y, con
filas [1, cos θᵢ, sen θᵢ] e yᵢ = 1/rᵢ. De c salen e = √(B² + C²)/A, la longitud del perihelio
ϖ = atan2(C, B) y a = 1/(A(1 − e²)).

**Métodos.**
- **Ecuaciones normales + Cholesky:** (MᵀM)c = Mᵀy; MᵀM es 3×3 simétrica definida positiva,
  MᵀM = LLᵀ, y se resuelven Lz = Mᵀy y Lᵀc = z.
- **QR por Gram–Schmidt modificado:** M = QR (Q con columnas ortonormales, R triangular 3×3) y
  Rc = Qᵀy. No forma MᵀM.
- **Condicionamiento:** κ(MᵀM) = κ(M)². Con un arco corto, cos θ y sen θ casi no cambian: las
  columnas de M son casi dependientes y κ se dispara. Las ecuaciones normales pierden ≈ log₁₀ κ(MᵀM)
  dígitos de 16; QR, la mitad.
- **Predicción:** con la órbita ajustada, la época sale de la media circular de
  Mᵢ − n·tᵢ (n = k/a^{3/2}) y la posición futura de la ecuación de Kepler por Newton.

**En MechaForge.** La órbita real de Ceres es la discontinua; el arco cian es lo observado; los
puntos son las observaciones y las barras rojas sus residuos (aumentados ×100 o más para que se
vean). Las órbitas ajustadas: naranja (Cholesky) y cian (QR). La línea tenue une la Tierra con
Ceres: es la visual de Piazzi. En el día de la reaparición se ven la predicción y la posición real
unidas por una línea roja. Controles: observaciones, arco observado, error de cada posición,
días hasta la reaparición y 🎲 otra semilla.

**Resultados (22 observaciones, reaparición 323 días después del final del arco).**

| Arco | Error de cada posición | κ(MᵀM) | a ajustado (real 2,7675 UA) | e (real 0,0785) | Error al reaparecer |
|---|---|---|---|---|---|
| 41 días (8,8°) | 0 | 2,8·10⁶ | 2,7675 | 0,0785 | 0,000° |
| 41 días | 0,01 % | 2,8·10⁶ | 2,866 | 0,104 | **0,26°** |
| 41 días | 0,1 % | 2,9·10⁶ | 5,47 | 0,52 | 2,12° |
| 200 días | 0,1 % | 4,3·10³ | 2,807 | 0,091 | 0,14° |
| 1680 días (una vuelta) | 0,1 % | 2,1 | 2,767 | 0,078 | 0,08° |

Cholesky y QR dan los mismos coeficientes hasta |Δc|/|c| ≈ 4·10⁻¹⁰: con κ = 2,8·10⁶ las ecuaciones
normales pierden ~6 dígitos, menos que el ruido de los datos. La diferencia se nota con arcos de 1 o
2 días y sin ruido (κ ~ 10¹²).

**Validación.** Sin ruido se recupera exactamente la órbita real. Con un error del 0,01 % la
predicción falla 0,26°, como Gauss (medio grado).

**Para el análisis.** ¿Por qué un error de 0,1 % en los datos da un semieje del doble? Relación
entre la longitud del arco, κ y el error de la predicción. ¿Cuándo conviene QR frente a las
ecuaciones normales?

---

## 3. ¿Cuándo estará Marte más cerca de la Tierra?

**Planteamiento.** Cada ~26 meses Marte se acerca a la Tierra (oposición). Los anuarios
astronómicos dan posiciones cada cierto número de días; ¿con qué precisión se puede sacar de esa
tabla el instante y la distancia del acercamiento?

**Modelo.** Posiciones heliocéntricas de la Tierra y Marte con los elementos keplerianos medios de
JPL (E. M. Standish, válidos de 1800 a 2050): a, e, I, L, ϖ, Ω con su ritmo por siglo. Anomalía
media M = L − ϖ, **ecuación de Kepler E − e sen E = M por Newton**, posición en el plano de la
órbita y tres rotaciones a la eclíptica. La función es d(t) = |r_Marte(t) − r_Tierra(t)|.

**Métodos.**
- Tabla (efeméride) cada Δ días desde el día 1 de un mes (los nodos no caen en el mínimo).
- **Menor valor de la tabla:** el nodo con menor d (error hasta Δ/2).
- **Parábola por 3 nodos (Lagrange cuadrática):** vértice
  t* = tᵢ + (Δ/2)(dᵢ₋₁ − dᵢ₊₁)/(dᵢ₋₁ − 2dᵢ + dᵢ₊₁).
- **Spline cúbico natural:** segundas derivadas Mᵢ del sistema tridiagonal
  hMᵢ₋₁ + 4hMᵢ + hMᵢ₊₁ = 6(Δᵢ − Δᵢ₋₁) con M₀ = Mₙ = 0 (algoritmo de Thomas); el mínimo es la
  raíz de S′(t) por bisección.
- **Referencia sin tabla:** sección áurea sobre d(t) evaluada directamente (tolerancia 10⁻⁶ días).

**En MechaForge.** La Tierra y Marte se mueven fecha a fecha, unidos por una línea con la
distancia. Los puntos y las líneas tenues sobre las órbitas son la tabla: la Tierra y Marte en cada
fecha de la tabla. Detrás, un tablero con d(t): la curva real (blanca), los nodos, el interpolante
lineal (gris), la parábola (naranja) y el spline (cian), con el mínimo de cada uno y su error en
horas; el cursor amarillo es la fecha de la animación.

**Resultados (Δ = 20 días).**

| Acercamiento | Método | Fecha del mínimo (UT) | Error | Distancia |
|---|---|---|---|---|
| 2025 | Menor valor de la tabla | 19 ene 2025 00:00 | +153,9 h | +688 539 km |
| | Parábola por 3 nodos | 12 ene 2025 13:03 | −1,1 h | +19 025 km |
| | Spline cúbico natural | 12 ene 2025 16:11 | +2,1 h | +18 859 km |
| | Referencia (sección áurea) | 12 ene 2025 14:07 | — | 96 085 787 km |
| 2027 | Menor valor de la tabla | 18 feb 2027 00:00 | −48,4 h | +69 381 km |
| | Parábola por 3 nodos | 19 feb 2027 23:57 | −0,5 h | +3 911 km |
| | Spline cúbico natural | 19 feb 2027 22:49 | −1,6 h | +2 873 km |
| | Referencia (sección áurea) | 20 feb 2027 00:25 | — | 101 403 300 km |

Error máximo de interpolación entre nodos: lineal 1,6 millones de km, spline 98 000–136 000 km
(orden h² frente a h⁴). La ecuación de Kepler converge en ~3 iteraciones de Newton.

**Validación.** NASA: 12 de enero de 2025 a 96,08 millones de km y 20 de febrero de 2027 (00:07 UT)
a 101,41 millones de km. La referencia cae el mismo día, a menos de 0,01 millones de km.

**Para el análisis.** Cambia Δ de 1 a 60 días: ¿cómo crece el error de cada método? ¿Por qué la
parábola local compite con el spline cerca del mínimo pero el spline gana en el error máximo?

---

## 4. Si la Tierra se detuviera, ¿cuánto tardaría en caer al Sol?

**Planteamiento.** Si la Tierra dejara de orbitar, caería en línea recta. La energía da la
velocidad en cada r y el tiempo es una integral… que no se puede calcular con las fórmulas
habituales porque el integrando es infinito en el punto de partida.

**Modelo.** Desde el reposo en r = R: v²/2 − GM/r = −GM/R, así que

  t = ∫₀ᴿ dr / √(2GM(1/r − 1/R)).

El integrando diverge como 1/√(R − r) en r = R: **integral impropia**, aunque convergente. Valor
exacto: t = (π/2)·R^{3/2}/√(2GM) = T/(4√2) = **64,5689 días**, con T el año.

**Métodos.**
- **Trapecio y Simpson:** evalúan f(R) = ∞ → fallan.
- **Punto medio y Gauss–Legendre:** no tocan los extremos, pero la singularidad los frena:
  error ∝ n^{−1/2} y n^{−1}.
- **Tanh-sinh (doble exponencial):** amontona los nodos junto a los extremos con pesos que caen
  más rápido que crece f; converge muy rápido. Se integra en w = R − r para no perder los nodos
  muy cercanos a R por redondeo.
- **Cambio de variable r = R sen²u:** el integrando pasa a ser 2R^{3/2} sen²u/√(2GM) en
  u ∈ [0, π/2], suave: trapecio y Simpson dan el valor exacto con pocos puntos.
- **EDO:** r̈ = −GM/r² con RK4 hasta la superficie del Sol; el instante del choque se interpola
  linealmente dentro del último paso.

**En MechaForge.** La Tierra cae por el eje; un fantasma sigue en la órbita normal. Sobre el camino,
la curva blanca es el integrando dt/dr y **cada barra es un nodo de la cuadratura elegida** (su
alto, el valor de f): las barras rojas marcan donde el método necesita f(R) = ∞. Con el cambio de
variable aparece la curva verde, ya suave.

**Resultados.**

| Método (n = 16) | Resultado (días) | Error | Evaluaciones |
|---|---|---|---|
| Trapecio | ∞ | — | 17 |
| Simpson | ∞ | — | 17 |
| Punto medio | 58,372 | 6,2 | 16 |
| Gauss–Legendre | 62,400 | 2,2 | 16 |
| Tanh-sinh | 64,5689074 | 1,4·10⁻¹⁴ | 29 |
| r = R sen²u + trapecio | 64,5689074 | < 10⁻¹⁴ | 17 |
| r = R sen²u + Simpson | 64,5689074 | < 10⁻¹⁴ | 17 |

Convergencia (error para n = 4, 8, 16, 32, 64): punto medio 12; 8,7; 6,2; 4,4; 3,1 (p = 0,50);
Gauss–Legendre 7,9; 4,2; 2,2; 1,1; 0,55 (p = 0,99).

EDO con RK4 hasta la superficie del Sol (exacto 64,5602 días): h = 0,1 d → 64,5409;
h = 0,01 d → 64,56015; h = 0,001 d → 64,56020. Llega a ~616 km/s.

**Validación.** Fórmula cerrada T/(4√2) y la del tiempo hasta un radio r,
t(r) = √(R³/2GM)(√(x(1 − x)) + arccos √x), x = r/R.

**Para el análisis.** ¿Por qué el orden de punto medio es ½ y no 2? ¿Qué hace el cambio de
variable con la singularidad? Compara cuadratura y EDO en coste y precisión.

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
- **Integradores:** Euler explícito (orden 1), Runge–Kutta 4 (orden 4) y Verlet de velocidad
  (orden 2, simpléctico: conserva una energía cercana a la real, sin deriva).
- **Perihelios:** cuando rₖ₋₁ > rₖ ≤ rₖ₊₁, el vértice de la parábola por los tres pasos da el
  instante τ, y el ángulo se interpola en τ con la parábola de Lagrange por θₖ₋₁, θₖ, θₖ₊₁.
- **Precesión medida:** pendiente de la recta de mínimos cuadrados de la longitud del perihelio
  ϖ(t), en ″ por siglo.
- **Extrapolación:** 43″/siglo son 5·10⁻⁷ rad por vuelta, del orden del propio error del
  integrador. Se exagera λ (0, 10⁴, …, 4·10⁴), se mide P(λ) y se ajusta por mínimos cuadrados
  P(λ) ≈ c₀ + c₁λ + c₂λ² (ecuaciones normales 3×3 por Cholesky). **c₁ es la predicción para λ = 1**;
  c₀ es la precesión que inventa el integrador (se descuenta sola) y c₂ la no linealidad de
  exagerar tanto. Con una recta (sin c₂) el resultado queda sesgado.

**En MechaForge.** Los tres integradores a la vez: Euler (rojo) se abre en espiral, RK4 (cian) y
Verlet (verde) siguen la elipse que gira (en la escena λ = 10⁵: 2,9° por vuelta). Cada perihelio
deja una marca y una línea al Sol: la roseta. Arriba, el tablero con P(λ) medido y la parábola
ajustada. «📐 Medir y extrapolar a λ = 1» repite la medida con el paso y las vueltas elegidos.

**Resultados (h = 0,1 días, 5 vueltas por λ).**

| Integrador | Deriva de energía | Precesión numérica (c₀) | c₁ (parábola) | Recta (sesgada) | Error de c₁ |
|---|---|---|---|---|---|
| Euler | 0,26 | 653 464″ | 24,2″ | 24,4″ | −18,8″ |
| RK4 | 1,1·10⁻¹⁰ | 4,7″ | **42,978″** | 43,583″ | −0,003″ |
| Verlet | 1,4·10⁻⁵ | −7 890″ | **42,969″** | 43,574″ | −0,012″ |

Con pasos mayores: RK4 da 42,977″ (h = 0,5), 42,852″ (h = 1) y 41,33″ (h = 2); Verlet 42,755″,
41,90″ y 42,09″.

**Validación.** Relatividad general: 42,98″ por siglo; observado (descontados los planetas):
42,98 ± 0,04″.

**Para el análisis.** ¿Por qué Verlet, con un error de energía mayor que RK4, no deriva? ¿Por qué
el ajuste lineal da 43,58″ y el cuadrático 42,98″? ¿Qué pasa con la extrapolación si el paso es
tan grande que la precesión numérica depende de λ?

---

## Límites del modelo

Están declarados en el panel 📐 Modelo de la aplicación:

- **Pregunta 1:** problema restringido y circular: los dos cuerpos giran en círculos y la nave no
  los perturba.
- **Pregunta 2:** simplificación del problema de Gauss. Se ajustan posiciones heliocéntricas
  (r, θ) en el plano de la eclíptica. Gauss solo tenía ángulos medidos desde la Tierra, y Ceres
  está inclinada 10,6°.
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
- R. L. Burden y J. D. Faires, *Análisis numérico* (raíces, interpolación, cuadratura, EDO).
