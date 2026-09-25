# Wiki — Taller de Pruebas de Carga y Rendimiento

> Mantenido como `wiki.md` en la raíz del repo durante el desarrollo; migrar a la wiki real del
> repositorio antes de la entrega final. Se actualiza de forma acumulativa en cada fase
> (ver MASTER_PLAN.md §3, paso 6).

---

## Inicio

Este taller evalúa el comportamiento del servicio `registraduria` (Spring Boot, endpoint
`POST /register`, base de datos H2 en memoria) bajo distintos niveles y patrones de carga,
usando **k6** como herramienta de generación de tráfico y medición. El objetivo no es solo
confirmar que el servicio responde, sino verificar que responde **correctamente** y **dentro de
los tiempos acordados** incluso cuando muchos clientes lo usan a la vez.

**Sistema bajo prueba**: `registraduria/`, un servicio con una única regla de negocio (registrar
un votante) expuesta por HTTP, respaldada por H2 en memoria, con Actuator habilitado para
observabilidad (`/actuator/health`, `/actuator/metrics/*`, `/actuator/prometheus`).

**Herramienta**: k6 (scripts en `perf/scripts/`), datasets en `perf/data/`.

---

## Tipos de pruebas

- **Baseline**: carga constante y baja (20 VUs), sin rampas. Sirve como punto de referencia
  "en calma" contra el cual se comparan todos los demás escenarios.
- **Load (carga esperada)**: rampa 0→200 VUs, sostiene, y baja. Simula el uso normal esperado
  en producción.
- **Stress**: lleva el sistema más allá de la carga esperada (200→600 VUs) para encontrar el
  punto de quiebre. En este sistema, el "quiebre" no fue una falla dura sino un techo de
  throughput (ver Resultados).
- **Spike**: subida súbita y breve (50→300→50 VUs) para observar si el sistema se recupera
  limpiamente después del pico.
- **Soak**: carga moderada sostenida por un período largo (100 VUs) para detectar degradación
  lenta — fugas de memoria, crecimiento de hilos, GC cada vez más frecuente — que no se ve en
  corridas cortas.
- **Regression**: corrida corta (20 VUs, 5 min) usada en Fase 2 para comparar dos builds del
  servicio (antes/después de un fix) bajo las mismas condiciones.
- **Arrival** *(fases posteriores según se necesite)*.

## Modelos de carga

- **Modelo cerrado (closed model)**: se fija el número de VUs; el throughput resultante depende
  de qué tan rápido responde el sistema. Usado en baseline, load, stress, spike, soak, regression.
- **Modelo abierto (open model)**: se fija la tasa de peticiones por segundo directamente: si el
  sistema no da abasto, la cola crece en vez de que el throughput simplemente baje. Usado en el
  escenario `arrival`.

---

## Plan de pruebas

### SLA / SLO / SLI

| Nivel | Definición | Valor para este taller |
|---|---|---|
| SLA | Promesa externa/de negocio | (fuera de alcance formal del taller; se documenta como referencia) |
| SLO | Objetivo interno medible | p95 < 300 ms, p99 < 800 ms, error rate < 1%, throughput ≥ 100 req/s |
| SLI | Indicador medido realmente | Lo reportado por k6 (`http_req_duration`, `http_req_failed`) y por Actuator (`http.server.requests`, hilos de Tomcat, GC, pool HikariCP) |

### Alcance

- Endpoint bajo prueba: `POST /register`.
- Datos: `perf/data/persons.csv` (datos simples, siempre válidos, usados por
  `register_person_k6.js`) y `perf/data/voters.csv` (512 filas cubriendo clases de equivalencia:
  `VALID`, `UNDERAGE`, `DEAD`, `INVALID_AGE`, con valores límite en edad, usado por
  `register_voter_k6.js`).
- Ambiente: local (localhost:8080), un solo nodo, base H2 en memoria, k6 y el servicio
  compartiendo la misma máquina (8 procesadores lógicos) — no representativo de producción
  distribuida, pero suficiente para el propósito pedagógico del taller. **Esto último importa
  para interpretar el throughput absoluto: ver Conclusiones técnicas.**
- Disciplina de ejecución: reiniciar el servicio entre escenarios (la base H2 vive mientras vive
  el proceso), para evitar falsos `DUPLICATED`; esperar a que `/actuator/health` responda `UP`
  antes de lanzar k6, para evitar una ráfaga inicial de conexiones rechazadas.

### Scripts

- `register_person_k6.js`: valida HTTP 200 + cuerpo `VALID`. Mide rendimiento puro.
- `register_voter_k6.js`: valida que la respuesta de negocio sea la *correcta* según el CSV
  (métrica `register_failed`), no solo que el HTTP responda. Mide correctud bajo carga.
- `perf/scripts/sample_actuator.ps1` *(Fase 2)*: muestrea `/actuator/prometheus` cada N segundos
  durante una corrida de k6 y guarda un CSV con percentiles de servidor, hilos de Tomcat, GC,
  CPU del proceso y (en el build corregido) uso del pool HikariCP.

---

## Ejecución

| Fecha | Escenario | Script | VUs / patrón | Duración | Notas |
|---|---|---|---|---|---|
| 2026-09-20 | baseline | register_person_k6.js | 20 VUs constantes | 5m | Servicio recién iniciado |
| 2026-09-20 | load | register_person_k6.js | 0→200→0 VUs (rampa) | 14m | Ejecutado justo después de baseline, sin reiniciar servicio (mismo proceso, IDs distintos por VU/iteración así que no hubo colisión) |
| 2026-09-20 | baseline (voters) | register_voter_k6.js | 20 VUs constantes | 5m | Primera corrida falló (65% `register_failed`) por reutilizar IDs de una corrida previa sin reiniciar el servicio; se repitió con el servicio reiniciado y dio 0% de fallos |
| 2026-09-21 | stress | register_person_k6.js | 200→600 VUs (rampa) | 10m | 22 fallos en el segundo 0 por arranque tardío del servicio (connection refused); descartados como ruido, no se repitió la corrida |
| 2026-09-21 | spike | register_person_k6.js | 50→300→50 VUs | 4m | Primera corrida con `sample_actuator.ps1` corriendo en paralelo |
| 2026-09-21 | load (pre-fix) | register_person_k6.js | 0→200→0 VUs (rampa) | 14m | Referencia previa al fix del defecto de pooling; resultado consistente con el `load` de Fase 1 |
| 2026-09-21 | soak (reducido) | register_person_k6.js | 100 VUs constantes | 25m (reducido de 2h, ver Decisions Log) | Sin degradación a lo largo del tiempo; CPU total de la máquina en 98% (8 procesadores lógicos) — el throughput medido refleja el límite de la máquina compartida, no solo del servicio |
| 2026-09-21 | regression ×4 (alternado) | register_person_k6.js | 20 VUs constantes | 5m c/u | 2 corridas con el build pre-fix y 2 con el build post-fix, alternadas (pre, post, pre, post) para aislar el efecto del fix del ruido de la máquina compartida |
| 2026-09-21 | load (post-fix) | register_person_k6.js | 0→200→0 VUs (rampa) | 14m | Misma configuración que el `load` pre-fix, tras aplicar el pool HikariCP |

---

## Resultados

### Fase 1

| Métrica | baseline | load | SLO | Resultado |
|---|---|---|---|---|
| p95 | 10.4 ms | 78.6 ms | < 300 ms | ✅ PASS |
| p99 | PASS (umbral verificado por k6; valor exacto no capturado — `summaryTrendStats` no incluía p(99) en esta corrida) | PASS (ídem) | < 800 ms | ✅ PASS |
| Error rate | 0% | 0% | < 1% | ✅ PASS |
| Throughput | 3672 req/s | 3512 req/s | ≥ 100 req/s | ✅ PASS |
| Correctud de negocio (voters, corrida limpia) | 100% correcto (`register_failed` rate = 0) | — | — | ✅ PASS |

### Fase 2 — stress, spike, soak (pre-fix)

| Métrica | stress | spike | soak (25m) | SLO | Resultado |
|---|---|---|---|---|---|
| p95 | 179.9 ms | 110.0 ms | 50.2 ms | < 300 ms | ✅ PASS (los 3) |
| p99 | 295.0 ms | 207.9 ms | 82.1 ms | < 800 ms | ✅ PASS (los 3) |
| max | 1,138 ms | 1,110 ms | 757 ms | — | outlier ~1.1s presente en las 3 corridas, no escala con VUs — hipótesis: evento puntual de arranque/warm-up, no efecto de carga |
| Error rate | 0.001% (22/2,077,936, ráfaga inicial) | 0% | 0% | < 1% | ✅ PASS (los 3) |
| Throughput | 3,463 req/s | 2,889 req/s | 3,599 req/s | ≥ 100 req/s | ✅ PASS (los 3) |

**Ninguno de los tres escenarios rompió el servicio.** El "quiebre" bajo stress fue un techo de
throughput (~3,500 req/s, ya presente desde 20 VUs) con la latencia creciendo por encolamiento,
no una falla dura. Spike se recuperó limpiamente: el p95 de servidor bajó de 58.7 ms en el pico a
3–5 ms en menos de un minuto tras el descenso de VUs. Soak no mostró degradación en 25 minutos
(hilos, GC y latencia se mantuvieron estables).

### Comparación cliente (k6) vs. servidor (Actuator) — run de `load`, pre-fix

| | k6 (cliente) | Actuator (servidor) |
|---|---|---|
| Media, toda la corrida | 41.4 ms | 3.8 ms |
| Mediana | 43.2 ms | ~1.15 ms |

Del total medido por el cliente, ~91% corresponde a tiempo fuera del propio temporizador del
servidor: red, y sobre todo espera antes de que un hilo de Tomcat tome la petición. Se descartó
agotamiento del pool de hilos de Tomcat como causa principal: `tomcat_threads_busy` nunca llegó a
200 (máximo configurado) durante `load`, con un pico de 140 y un promedio de ~23.

### Defecto de connection pooling: antes y después del fix

Ver `defectos.md` (Defecto 01) para el detalle completo de evidencia y metodología. Resumen:

| Métrica | Pre-fix | Post-fix | Cambio |
|---|---|---|---|
| p95 (load) | 83.6 ms | 31.5 ms | −62% |
| p99 (load) | 145.4 ms | 47.4 ms | −67% |
| Throughput (load) | 3,392 req/s | 8,104 req/s | +139% |
| GC pausas / 1,000 req (regression, aislado) | ~0.20 | ~0.16 | −20% |
| CPU medio de proceso (regression, aislado) | ~0.41 | ~0.35 | −15% |
| Error rate | 0% | 0% | sin cambio |

La comparación se hizo en dos capas: 4 corridas cortas alternadas (`regression`) para aislar el
efecto del fix del ruido de la máquina compartida, y luego una comparación directa de `load`
completo antes/después. Las dos coinciden en dirección (mejora en todas las métricas), aunque la
magnitud en `load` es mayor — plausible, dado que a 200 VUs el ahorro de tiempo por conexión
también libera hilos de Tomcat antes, lo cual no ocurre igual a 20 VUs.

---

## Conclusiones técnicas

**Fase 1**: bajo baseline y load (20–200 VUs), el servicio cumple holgadamente todos los SLOs
definidos, y la regla de negocio es 100% correcta bajo carga moderada. El defecto de pool de
conexiones conocido de antemano por el diseño del taller (`RegistryRepository.getConnection()`
abre una conexión nueva por operación) **no se manifestó** a este nivel de concurrencia.

**Fase 2**:

- **El "punto de quiebre" de este sistema, en este ambiente, es un techo de throughput
  (~3,500 req/s), no una falla.** Se alcanza desde niveles de concurrencia bajos (ya visible en
  baseline de Fase 1) y no cambia sustancialmente entre 20 y 600 VUs — lo que cambia es cuánto
  tiempo esperan las peticiones adicionales, es decir, la latencia sube por encolamiento.
- **Ese techo es, en gran parte, de la máquina, no solo del servicio.** Durante `soak`, el CPU
  total del equipo (8 procesadores lógicos) estuvo en 98%, con el proceso Java en ~55% y k6 en
  ~25%. Esto es una limitación conocida del ambiente de pruebas (un solo laptop generando carga y
  sirviéndola) y debe leerse así en cualquier número de throughput absoluto reportado en este
  taller — son válidos para comparar builds entre sí, no como cifra de capacidad del servicio en
  un ambiente de producción real.
- **La brecha entre latencia de cliente y de servidor (~91% del tiempo total) es esperable y no
  es, en sí misma, un defecto**: es el costo de red más el tiempo que una petición espera antes
  de que un hilo la atienda. Se descartó el agotamiento de hilos de Tomcat como causa principal a
  200 VUs (nunca se llegó al máximo de 200 hilos ocupados simultáneamente).
- **El defecto de pooling de conexiones, diseñado deliberadamente en el taller, sí estaba
  presente** (`DriverManager.getConnection()` por cada llamada, 2 conexiones por request válido)
  y sí tenía un costo medible — no en forma de fallas o incumplimiento de SLO (H2 en memoria es
  demasiado rápido para eso), sino en CPU y frecuencia de GC. Corregirlo con un pool HikariCP dio
  una mejora medible y repetible: ~15–20% menos CPU/GC por request (aislado, sin ruido de
  throughput) y una mejora mayor en la comparación directa de `load` (p95 −62%, p99 −67%,
  throughput +139%). Contra una base de datos real en red, donde abrir una conexión cuesta
  milisegundos y no microsegundos, se espera que el mismo defecto sea bastante más grave.
- **Analogía**: el servicio sin pool es como un banco donde cada cajero tiene que ser contratado,
  entrenado y despedido para atender a un solo cliente, en vez de tener un cajero fijo que
  atiende a varios clientes seguidos. Con pocos clientes (baja concurrencia) el costo de
  contratar/despedir es insignificante frente a la atención misma; con muchos clientes seguidos,
  ese costo repetido empieza a notarse en el cansancio general del banco (CPU, GC), aunque cada
  cliente individual todavía sea atendido a tiempo.

---

## Matriz de rendimiento (Fase 3)

| Escenario | Modelo de carga | Duración | Build | SLO (p95 / p99 / error) | Resultado | Artefacto |
|---|---|---|---|---|---|---|
| baseline | 20 VUs constantes | 5m | pre-fix | <300ms / <800ms / <1% | ✅ PASS — p95 10.4ms, error 0% | `perf/results/summary-baseline.json` |
| load | 0→200→0 VUs (rampa) | 14m | pre-fix (Fase 1) | <300ms / <800ms / <1% | ✅ PASS — p95 78.6ms | `perf/results/summary-load-phase1.json` |
| baseline (voters) | 20 VUs constantes | 5m | pre-fix | <1% register_failed | ✅ PASS — 0% tras reinicio | `perf/results/summary-voters-baseline.json` |
| stress | 200→600 VUs (rampa) | 10m | pre-fix | <300ms / <800ms / <1% | ✅ PASS — p95 179.9ms, techo de throughput ~3,500 req/s, no falla dura | `perf/results/summary-stress.json` |
| spike | 50→300→50 VUs | 4m | pre-fix | <300ms / <800ms / <1% | ✅ PASS — p95 110.0ms, recuperación <1min | `perf/results/summary-spike.json` |
| soak | 100 VUs constantes | 25m (reducido de 2h) | pre-fix | <300ms / <800ms / <1% | ✅ PASS — p95 50.2ms, sin degradación | `perf/results/summary-soak.json` |
| regression ×4 (alternado) | 20 VUs constantes | 5m c/u | 2× pre-fix, 2× post-fix | <300ms / <800ms / <1% | ✅ PASS (los 4) — usado para aislar el efecto del fix (GC/CPU), no para el gate | `perf/results/summary-regression-{prefix,postfix}-{1,2}.json` |
| load | 0→200→0 VUs (rampa) | 14m | pre-fix (re-run, Fase 2) | <300ms / <800ms / <1% | ✅ PASS — p95 83.6ms | `perf/results/summary-load-prefix.json` |
| load | 0→200→0 VUs (rampa) | 14m | **post-fix** (referencia actual) | <300ms / <800ms / <1% | ✅ PASS — p95 31.5ms (−62% vs. pre-fix) | `perf/results/summary-load.json` |

Todas las corridas, en ambos builds, cumplieron los tres SLOs (p95<300ms, p99<800ms,
error<1%) durante todo el taller — el defecto de pooling encontrado en Fase 2 degradó
rendimiento y costo de CPU/GC, pero nunca hizo que el servicio incumpliera el SLO a esta escala
(ver `defectos.md`, Defecto 01, sección "Causa probable" para por qué se espera que sea distinto
contra una base de datos real en red). El job `k6-quick-gate` de CI corre `baseline` (persona y
voter) en cada PR como gate automático de estos mismos SLOs; `k6-extended` corre
stress/spike/soak por disparo manual o nocturno — ver sección CI/CD más abajo.

---

## CI/CD

`.github/workflows/perf.yml` (copiado de `perf/ci/github-actions.yml`) define dos jobs:

- **`k6-quick-gate`** — en cada Pull Request. Empaqueta el servicio, lo levanta, espera
  `/actuator/health`, corre `baseline` de `register_person_k6.js` y de `register_voter_k6.js`
  (~5 min cada una), y publica `summary-*.json` como artefacto. Los `thresholds` definidos
  dentro de cada script (`p(95)<300`, `p(99)<800`, `rate<0.01` en errores HTTP y en
  `register_failed`) son el gate: si se incumplen, k6 sale con código distinto de 0 y el job
  falla — no hace falta lógica de comparación adicional en el YAML.
- **`k6-extended`** — por `workflow_dispatch` (con un input opcional `soak_duration`,
  default `25m`) o de forma nocturna (`schedule`, cron `0 3 * * *`). Corre `stress`, reinicia el
  servicio, corre `spike`, reinicia de nuevo, corre `soak`. No corre en PR porque los tres
  escenarios juntos suman más de 40 minutos y bloquearían la revisión.

**Verificación pendiente de ejecución real**: este archivo fue escrito y validado
sintácticamente (YAML parseado sin errores) en este chat, pero **no pude ejecutarlo** — no hay
runner de GitHub Actions disponible en este entorno de trabajo. En particular, dos ítems del
`todo.md` quedan como verificación pendiente del usuario tras el primer push:
1. Confirmar que `k6-quick-gate` efectivamente arranca el servicio, espera `/actuator/health`, y
   corre de punta a punta en un PR real.
2. Confirmar el comportamiento del gate ante un umbral incumplido: bajar temporalmente un
   threshold en `register_person_k6.js` (p. ej. `'http_req_duration{status:200}': ['p(95)<1']`),
   hacer un PR, confirmar que el job falla en rojo, y revertir el cambio.

Ver `handoff-phase-3.md` para el detalle de esta limitación y cómo verificarla.

---

## Mejoras propuestas

- **Pool de conexiones dimensionado por ambiente, no fijo en 20.** `hikari_pending` nunca superó
  0 en este taller (ver `defectos.md`), pero el tamaño fue elegido por default de HikariCP, no
  medido contra una base de datos real en red — contra Postgres/MySQL remoto, con latencia de
  conexión de milisegundos en vez de microsegundos, 20 podría no alcanzar bajo `stress`
  (600 VUs). Antes de llevar esto a producción, repetir `stress` contra una BD real y observar
  `hikaricp_connections_pending`.
- **Separar el gate de latencia del de "resultado de negocio" con más granularidad.** Hoy
  `register_voter_k6.js` en CI solo corre `baseline`; sería útil, sin alargar el PR gate, agregar
  un escenario corto de `voters` con datos que fuercen algunos `DUPLICATED` a propósito, para
  confirmar que el *rate* de negocio se mide correctamente y no solo el *happy path*.
- **Reemplazar `sample_actuator.ps1` por un equivalente bash/curl** para poder correr la misma
  observabilidad (GC, hilos Tomcat, pool Hikari) dentro de `k6-extended` en CI, donde no hay
  PowerShell garantizado — hoy esa instrumentación solo se usó manualmente en Windows durante
  Fase 2, y el job de CI no la captura.
- **Investigar el outlier de ~1.1s** que aparece en stress/spike/load pre-fix a concurrencias muy
  distintas (ver handoff-phase-2.md, "Open issues") — no bloqueó ningún SLO, pero tampoco se
  explicó; un profiler (async-profiler o JFR) durante una corrida corta lo confirmaría o lo
  descartaría como evento de warm-up.
- **No confiar en throughput absoluto como gate de CI** — confirmado ruidoso (~60% de variación
  run-a-run) en la máquina compartida de Fase 2. Si se agrega un threshold de throughput al gate
  en el futuro, usar un margen amplio o preferir las métricas ya identificadas como estables
  (GC/CPU por request) en su lugar.

---

## Reflexión final

**¿Cuál fue la métrica más sensible?** El p95/p99 de `load` (200 VUs) — no porque haya fallado
nunca (siempre estuvo dentro del SLO, incluso pre-fix), sino porque fue la métrica donde el
defecto de pooling se hizo más visible y donde la mejora del fix fue mayor en términos
relativos (−62% p95, −67% p99), más que en `regression` a 20 VUs. La razón, documentada en
Resultados: a mayor concurrencia, el ahorro de tiempo por conexión también libera hilos de
Tomcat antes, componiendo el efecto.

**¿Cuál fue el principal cuello de botella y su mitigación?** La ausencia de *connection
pooling* en `RegistryRepository.getConnection()` (`DriverManager` por cada llamada, 2 conexiones
por request válido — ver `defectos.md`, Defecto 01). Contra H2 en memoria el costo fue de
CPU/GC, no de SLO incumplido; se mitigó introduciendo un pool HikariCP fijo (20 conexiones) en
`RegistryConfig`, validado con 4 corridas alternadas de `regression` (para aislar el efecto del
ruido de máquina) y una comparación directa de `load` antes/después.

**¿Qué se rediseñaría?** Dos cosas: (1) correr al menos una tanda de pruebas contra una base de
datos real en red desde el principio, no solo H2 en memoria — el propio taller señala que el
defecto de pooling "se espera bastante más grave" en ese caso, y ahora mismo eso es una hipótesis
documentada, no una medición; y (2) automatizar la comparación pre/post-fix (regression
alternado) como un script reutilizable en vez de un procedimiento manual de 4 corridas — sería
la forma natural de convertir esa metodología en parte del CI extendido para futuros defectos de
rendimiento, no solo este.
