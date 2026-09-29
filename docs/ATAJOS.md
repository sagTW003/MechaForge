# Atajos de teclado — MechaForge

## Cámara
| Control | Acción |
|---|---|
| Rueda del ratón | Zoom (acercar/alejar) |
| Botón central | Orbitar alrededor del punto de interés |
| `Mayús` + botón central | Desplazamiento (pan) |
| `Alt` + clic izquierdo | Orbitar (alternativa) |
| `F` | Centrar la cámara en el origen |

## Edición
| Control | Acción |
|---|---|
| Clic izquierdo | Colocar la pieza elegida / seleccionar una pieza |
| Arrastrar una pieza | Moverla sobre el suelo (X/Z) |
| Arrastrar **sobre otra pieza** | **Encaja** automáticamente encima o contra su cara (opción "Encajar" de la barra) |
| Mantener `Z` + arrastrar | Mover en altura (vertical) |
| Flechas | Mover por rejilla (X/Z) |
| `Re Pág` / `Av Pág` | Subir / bajar (altura) |
| Clic derecho / `Esc` | Cancelar colocación / deseleccionar |
| **Gizmo 3D** | Con una pieza seleccionada: arrastra una **flecha** (mover en X/Y/Z) o un **anillo** (rotar sobre X/Y/Z) |
| `W` / `E` | Gizmo en modo **mover** / **rotar** |
| `R` | Rotar la pieza en **Y** (paso configurable) |
| `Mayús+R` / `Alt+R` | Rotar en **X** / en **Z** |
| `1` / `2` / `3` | Paso de rotación **15° / 45° / 90°** |
| *(automático)* | **Encaje inteligente**: al acercar una pieza, se ajusta a orificios de placas, ejes, extremos y ranuras en T de perfiles; un **anillo verde** marca el punto y el fantasma se vuelve verde |
| `Supr` | Eliminar la pieza seleccionada (o la **unión** seleccionada) |
| Clic en la esfera numerada de una unión | Seleccionar esa unión (también desde el panel *Uniones*) |
| `Ctrl+D` | Duplicar la pieza seleccionada |
| Soltar una resistencia/LED/integrado sobre la protoboard | Sus patas se **insertan** en los agujeros (un DIP debe cruzar el canal central) |

## Laboratorio matemático (∑)
| Control | Acción |
|---|---|
| Arrastrar (clic izq. o der.) | Orbitar · `Mayús` + clic der. o botón central: desplazar · rueda: zoom |
| `1` / `2` / `3` | Vista perspectiva / superior 2D / isométrica |
| `F` | Encuadrar el siguiente punto crítico |
| `P` | Alternar la herramienta Orbitar / **Perturbar** |
| `Espacio` / `R` | Pausa / reiniciar el módulo |
| `H` | Activar o desactivar el seguimiento de manos (🖐 Manos) |
| `Esc` | Volver a MechaForge |

### Gestos con la mano (🖐 Manos)
| Gesto | Acción |
|---|---|
| ☝ Índice extendido | Mover el cursor |
| 🤏 Pellizco pulgar–índice | Girar la gráfica 3D · desplazar la 2D · ajustar un deslizador · pulsar un botón |
| 🤏🤏 Pellizco con las dos manos | Zoom (separar = acercar) |
| ✊✊ Las dos manos en puño | Mover la escena en 3D: arrastrar · acercar/alejar las manos = profundidad · girar = rotar |
| 🖐 Palma abierta | Pausa; mantenida 1 s reinicia la vista |

## Multímetro (📟)
| Control | Acción |
|---|---|
| Arrastrar una sonda | Moverla; cerca de un terminal hace snap y al soltar queda enganchada |
| Clic en un terminal | Coloca la sonda activa (alterna roja/negra) |
| Clic o rueda sobre el selector | Cambia el modo (OFF, V⎓, V~, A⎓, Ω, continuidad) |
| Clic derecho sobre una sonda | La devuelve junto al multímetro |
| Clic derecho en vacío | Sale del modo multímetro |
| `Ctrl+C` / `Ctrl+V` | Copiar / pegar pieza |
| `M` | Copia **simétrica** respecto del plano YZ (x → −x) |
| `G` | Activar/desactivar snapping a la rejilla |

## Simulación y uniones (Fase 2)
| Control | Acción |
|---|---|
| `Espacio` | Iniciar / detener la simulación |
| Botón `⟲ Reiniciar` | Volver al estado inicial |
| `P` / botón `⏸` | Pausa / reanudar |
| `.` / botón `⏭` | Avanzar un paso físico (1/120 s) en pausa |
| Selector `1.0×` | Cámara lenta: 1×, 0.5×, 0.25×, 0.1× |
| Botón `🔗 Conectar` | Unir dos piezas: clic en la 1.ª y luego en la 2.ª, elige el tipo (fija/bisagra/deslizadera/rótula/engranaje), límites y motor |

Durante la simulación, selecciona una pieza para ver su **telemetría en vivo**
(posición, velocidad, velocidad angular, masa) y el **centro de masa** del conjunto.

## Electrónica, cableado y soldadura
| Control | Acción |
|---|---|
| Botón `🔌 Cablear` | Los terminales **brillan** al acercar la punta del cable (verde = compatible, ámbar = alimentación↔tierra). Clic en uno y luego en otro; se ve un **cable provisional** que sigue al cursor |
| Clic derecho (cableando) | Cancelar el cable en curso (otro clic derecho sale del modo) |
| Panel *Circuito* → *Color del cable* | Automático (VCC rojo, GND negro, señal azul) o color fijo |
| Botón `🔥 Soldar` | Clic en el extremo de un cable: el cautín se acerca, el estaño **se funde** (líquido brillante) y **solidifica** en un menisco |

## Entorno y gráficos
| Control | Acción |
|---|---|
| Panel *Entorno y gráficos* | Entorno **Estudio / Taller / Exterior** o un **HDRI** propio; hora del día y **ciclo día/noche**; antialiasing **TAA+MSAA / SMAA / FXAA**; bloom; profundidad de campo con autoenfoque; exposición |

## Proyecto
| Control | Acción |
|---|---|
| `Ctrl+Z` | Deshacer |
| `Ctrl+Y` | Rehacer |
| `Ctrl+S` | Guardar proyecto |
| `Ctrl+O` | Abrir proyecto |

## Ayuda
| Control | Acción |
|---|---|
| `H` / `F1` | Mostrar/ocultar la ayuda dentro de la app |

> Los pasos de **rejilla** (1/5/10/20/50 mm) y **rotación** (5/15/45/90°) se
> eligen en la barra superior.
