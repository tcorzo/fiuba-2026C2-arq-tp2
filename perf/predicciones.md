# Predicciones

Hipótesis con predicción numérica de cada prueba de carga, como pide el
enunciado (README.md, *Predicción antes de medir*).

**Regla:** la predicción de un caso se commitea **antes** que sus resultados
(`perf/results/<caso>/`). El historial de commits es la prueba. Una predicción
no se edita después de medir: la comparación con el resultado y la explicación
de la diferencia van en el informe.

Cada entrada lleva:

- **Caso y escenario:** configuración (nodos, táctica) y escenario de Artillery.
- **Métrica y predicción:** al menos una métrica con un número. Por ejemplo,
  latencia mediana o p95, errores, uso de CPU de los nodos o de ARCA.
- **Razonamiento:** por qué ese número, a partir del código, la infraestructura
  y los resultados del TP 1.

Para el caso escalado, la predicción dice además si el throughput escala
proporcionalmente a la cantidad de nodos y, si no, qué componente lo impide.

## Latencia de base

<!-- Medición contra `/`, sin carga, antes de las pruebas. -->

## Caso 1 nodo

- **Caso:** 1 nodo del VMSS (`Standard_F1als_v7`, 1 vCPU), un proceso de Node
  en pm2. Postgres `B_Standard_B1ms` y ARCA en ACI con 0,5 vCPU. Código de
  `0fdb4ef`. Evidencia de la infraestructura en `evidencia/1-node/measured/`.
- **Escenario:** `baseline.yaml`, entorno `ramp`: ocho escalones de 60 s a 10,
  25, 50, 75, 100, 150, 200 y 300 rps. Mezcla: 40 % `POST /exchange`, 30 %
  `GET /rates`, 20 % `GET /accounts` y 10 % `GET /log`. Es la misma rampa y la
  misma mezcla que la ejecución final del TP 1.
- **Generador de carga:** Buenos Aires, ethernet cableada. Latencia de base
  contra `/`: mediana de 169 ms y p95 de 172,5 ms
  (`perf/results/baseline/root-tcorzo.json`).

### Predicciones

| # | Métrica | Predicción |
|---|---|---|
| P1 | Mediana de `GET /rates` en el cliente, escalones de 10 a 100 rps | 171 ms |
| P2 | Mediana de `arvault.arca.validation.duration` (Datadog), escalones de 10 a 100 rps | 370 ms |
| P3 | Mediana de `arvault.exchange.processing.duration` (Datadog, sin ARCA), escalón de 10 rps | 355 ms |
| P4 | p95 de `POST /exchange` en el cliente, escalón de 10 rps | 1.040 ms |
| P5 | Respuestas `502 ARCA_UNAVAILABLE` antes del quiebre | 24 % de los exchanges, 10 % de todos los requests |
| P6 | Respuestas `403 ARCA_REJECTED` | 25 % de los exchanges, 10 % de todos los requests |
| P7 | Último escalón atendido completo (sin timeouts y con el 95 % de las respuestas) | 150 rps |
| P8 | CPU del nodo en el escalón de 150 rps | menos del 50 % |
| P9 | Componente que limita (se verifica con `sessions_by_wait_event_type`, dimensión `Lock`, de Azure Monitor) | Postgres, en el camino de escritura del exchange |

### Razonamiento

- **P1.** `GET /rates` no llama a ARCA. Hace una consulta a Postgres dentro de
  la misma región. En el TP 1 su mediana era de 1 ms en el servidor. Le sumamos
  la latencia de base, porque Artillery mide el `response_time` sin el
  connect. Ese tiempo coincide con un RTT.
- **P2.** ARCA respondió con una mediana de 371 ms en 200 llamadas desde el
  jumpbox (issue #14). Suponemos que esos 370 ms son espera y no CPU: con
  0,5 vCPU, ARCA tendría que atender varias llamadas a la vez sin demorarse más.
- **P3.** `arvault.exchange.processing.duration` empieza después de la validación con ARCA. Mide
  lo mismo que en el TP 1: las dos transferencias concurrentes de 200 a 400 ms
  (H-12) más las consultas a Postgres. En la ejecución final del TP 1, la
  mediana del exchange a 10 rps fue de 354 ms.
- **P4.** Un exchange aprobado suma el RTT (unos 170 ms), ARCA (hasta 502 ms
  observados) y el exchange (p95 de 407 ms en el TP 1). El p95 del endpoint
  mezcla aprobados, rechazados y fallados. Los rechazos y los 502 son más
  rápidos, así que el p95 queda en la cola de los aprobados.
- **P5 y P6.** En el issue #14, ARCA respondió 102 aprobaciones, 50 rechazos y
  48 errores `500` en 200 DNIs aleatorios. El servicio no reintenta: cada
  `500` es un `502`. Los exchanges son el 40 % del tráfico. La carga no cambia
  estas proporciones hasta el quiebre, porque dependen de ARCA y no del nodo.
- **P7 y P9.** En la ejecución final del TP 1, la mezcla se quebró después de
  150 rps (atendió 150,5 ok/s y a 200 rps tuvo 2.720 timeouts). La causa fue
  la contención sobre las filas de las cuentas internas en Postgres (hot
  row). Acá hay dos efectos en sentidos opuestos:
  - A favor: sólo los exchanges aprobados (la mitad) llegan a Postgres. Los
    rechazados y los fallados terminan antes de escribir.
  - En contra: el nodo tiene un solo pool de 10 conexiones, contra 3 pools de
    10 en el TP 1. Una transacción que espera un lock retiene su conexión. Cada
    consulta además cruza la red hasta Postgres, con TLS, en lugar de quedarse
    en la red de Docker. Eso alarga el tiempo que cada transacción retiene el
    lock.
  Suponemos que los dos efectos se compensan y el quiebre queda en 150 rps.
  Cuando el pool se agota, también esperan las lecturas: `GET /rates` sube
  junto con el exchange, como en el TP 1.
- **P8.** El proceso de Node no hace trabajo pesado: espera a ARCA, a las
  transferencias y a Postgres. En el caso base del TP 1, un proceso con 1 core
  atendió 200 rps con el 67 % de la CPU, y casi toda se iba en serializar el log
  (H-11), que ya no existe.

### Qué cambiaría la predicción

- **Si los 370 ms de ARCA son CPU y no espera,** ARCA atiende menos de 2
  llamadas por segundo con 0,5 vCPU. Entonces ARCA limita desde el escalón de
  10 rps (4 exchanges por segundo): las validaciones superan el timeout de 2 s
  y los `502` pasan a tener `reason=timeout`.
- **Si Postgres agota sus créditos de CPU** (B1ms es burstable), el lock se
  retiene más tiempo y el quiebre baja de 150 rps.
- **Cada `502` escribe un stack trace en el log** (error handler). Si eso pesa
  en la CPU del nodo, P8 falla antes que P7.

## Caso 1 nodo, segunda ejecución: sesiones

La primera ejecución midió al generador de carga, no al servicio. Desde
150 rps, el generador resolvía el nombre del load balancer por DNS a unos
134 por segundo (`4a679f3`). Con `/etc/hosts`, perdía SYNs antes de Azure por
encima de unas 200 conexiones nuevas por segundo (`353902f`). Las predicciones
P1 a P9 quedan como estaban, comparadas con esa ejecución.

- **Caso:** el mismo de arriba, sin cambios en la infraestructura
  (`evidencia/1-node/measured/`).
- **Escenario:** `sessions.yaml`, entorno `ramp` (`4ecfef0`). La mezcla y los
  bodies de `baseline.yaml`, pero cada usuario virtual manda su request 4 veces
  por una sola conexión. Escalones de 60 s a 10, 25, 50, 75, 100, 150, 200,
  300, 400, 600 y 800 rps.
- **Generador de carga:** el mismo equipo, con el load balancer en
  `/etc/hosts` (`32eaed5`).

### Predicciones

| # | Métrica | Predicción |
|---|---|---|
| S1 | Mediana de `GET /rates` en el cliente, escalones de 10 a 300 rps | 171 ms |
| S2 | Último escalón completo (al menos el 99,5 % de los requests con respuesta) | 600 rps |
| S3 | CPU del nodo (user + system, Datadog) en el escalón de 400 rps | 45 % |
| S4 | Componente que limita, en el escalón de 800 rps | El proceso de Node del nodo: CPU por encima del 85 % y lag del event loop por encima de 50 ms |
| S5 | Esperas `Lock` de Postgres (`sessions_by_wait_event_type`, máximo por minuto) | 0 o 1 en todos los escalones |
| S6 | CPU de Postgres (`cpu_percent`) en el escalón de 600 rps | 65 % |

### Razonamiento

Usamos la primera ejecución hasta 150 rps, donde el generador no limitaba.

- **S1.** Igual que P1. La sesión no cambia el camino de `GET /rates` en el
  servidor. Artillery mide el `response_time` sin el connect, así que reusar la
  conexión no lo cambia.
- **S3 y S4.** A 150 rps, el nodo usó un 18 % de CPU (user + system) y el lag
  máximo del event loop fue de 8 ms. Si la CPU crece en proporción a los
  requests, llega al 100 % cerca de 830 rps. Un proceso de Node usa un solo
  core, y el agente de Datadog comparte esa vCPU. Por eso esperamos el quiebre
  antes: el 45 % a 400 rps y la saturación a 800.
- **S5.** Las transferencias de 200 a 400 ms corren fuera de toda transacción.
  `reserve()` es un solo `UPDATE`. El crédito y el log son una transacción corta
  al final (`node/exchange.js`). Cada fila caliente queda bloqueada unos pocos
  milisegundos. A 150 rps no hubo ninguna espera `Lock`. Eso descarta el hot row
  del TP 1, que retenía el lock durante las transferencias.
- **S6.** A 150 rps, Postgres usó un 17 % de CPU. En proporción, son un 65 % a
  600 rps. B1ms es burstable, pero tiene 138 créditos y no consumió ninguno a
  150 rps. Una rampa de 11 minutos no los agota.
- **S2.** Se sigue de S4: el escalón de 600 rps es el último antes de que el
  nodo sature.
- **Lo que no limita.** ARCA usó 20 milicores de sus 500 a 150 rps, y su mediana
  fue de 300 ms en el servidor, estable. El pool de 10 conexiones retiene cada
  conexión pocos milisegundos por request.

### Qué cambiaría la predicción

- **A 800 rps, el generador abre 200 conexiones nuevas por segundo.** Es el
  borde de lo que su red entregó sin perder SYNs. Si el contador de
  retransmisiones de SYN del generador crece, ese escalón mide la red.
- **Dentro de una sesión, cada request espera al anterior.** Si el nodo se
  demora, el generador manda menos de lo ofrecido. El quiebre aparece más
  suave y puede parecer más alto.
- **Si cada `502` escribe un stack trace,** la CPU por request crece con los
  rechazos de ARCA, y S3 queda corta.

## Caso 1 nodo, ejecución final: rampa con pool

La segunda ejecución empezó a quebrarse a 800 rps y terminó 40 s después, sin
mostrar qué pasa más arriba. Esta ejecución sigue la rampa del TP 1 y la
extiende hasta 1.000 rps.

- **Caso:** el mismo, redesplegado el 15 de noviembre con el código de
  `measured/1-node-sessions` (`evidencia/1-node/2026-11-15/`).
- **Escenario:** `baseline.yaml`, entorno `pool-ramp` (`dd2c207`). La mezcla de
  la primera ejecución, un request por usuario virtual y llegadas que no esperan
  respuestas, como en el TP 1. Escalones de 60 s a 10, 25, 50, 75, 100, 150,
  200, 300, 400, 600, 800 y 1.000 rps. Los requests comparten conexiones
  keep-alive (`http.pool`).
- **Generador de carga:** el mismo equipo. Contra `/`, llegó a 1.000 rps sin
  errores y con 469 conexiones (`7dc48a6`).

### Predicciones

| # | Métrica | Predicción |
|---|---|---|
| F1 | Último escalón completo (al menos el 99,5 % de los requests con respuesta) | 600 rps |
| F2 | Respuestas por segundo, máximo sostenido en un escalón | 700 |
| F3 | p50 de `GET /rates` en el servidor (Datadog), escalón de 800 rps | más de 100 ms |
| F4 | Requests sin respuesta en el escalón de 1.000 rps | más del 25 % |
| F5 | CPU del nodo (user + system, Datadog), en todos los escalones | menos del 60 % |
| F6 | Esperas `Lock` de Postgres (máximo por minuto) | 0 hasta 600 rps, 1 o más en 800 y 1.000 rps |
| F7 | Latencia de `GET /rates` en el cliente menos su p50 en el servidor, escalones de 10 a 600 rps | 169 a 175 ms (la latencia de base) |

### Razonamiento

Partimos de la segunda ejecución, sobre la misma infraestructura y el mismo
código.

- **F1 y F2.** Con sesiones, el nodo atendió 600 rps completos. A 800 rps
  respondió 796 por segundo durante 10 s y después cayó. Ese pico duró poco, así
  que el máximo sostenido está entre 600 y 800 rps.
- **F3.** A 800 rps con sesiones, el p50 de `GET /rates` subió de 1 a 585 ms.
  Acá las llegadas no esperan respuestas: la cola crece más rápido.
- **F4.** Si el nodo sostiene 700 respuestas por segundo, a 1.000 rps sobran
  300 requests por segundo. Se acumulan hasta el timeout de 8 s del agente de
  Artillery, así que más del 25 % queda sin respuesta.
- **F5.** Con sesiones, el nodo usó un 37 % a 600 rps y un 52 % de máximo a
  800 rps. La CPU no limitó. El pool no cambia el trabajo por request en el
  servidor.
- **F6.** Con sesiones, las esperas `Lock` aparecieron recién en la última
  muestra, al final del escalón de 800 rps.
- **F7.** `GET /rates` tarda 1 ms en el servidor. Si el generador no agrega
  demora, el resto es la latencia de base, 169 ms de mediana. El generador usó
  toda su CPU contra `/` desde 600 rps, pero la latencia no subió.

### Qué cambiaría la predicción

- **Si el pool de 10 conexiones no es lo que limita,** F3 falla: `GET /rates`
  sigue en 1 ms a 800 rps y el límite es otro componente.
- **Si el generador agrega demora,** F7 falla en los escalones altos y esos
  escalones miden el generador.
- **Con las llegadas abiertas, ARCA recibe hasta 400 validaciones por segundo.**
  Si su p50 sube de 300 ms, el límite pasa a ARCA.

## Caso escalado

## Tácticas
