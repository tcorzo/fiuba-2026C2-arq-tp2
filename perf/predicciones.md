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

## Caso escalado

**Hipótesis:** el throughput no se duplica con 2 nodos. El límite del caso 1
nodo fue la escritura sobre las cuentas internas en Postgres, y un segundo nodo
no la acelera. El servicio deja de atender completo en el mismo escalón que con
1 nodo.

- **Caso:** 2 nodos del VMSS (`Standard_F1als_v7`, 1 vCPU cada uno), con un
  proceso de Node en pm2 por nodo. Todo lo demás es igual al caso 1 nodo:
  Postgres `B_Standard_B1ms` y ARCA en ACI con 0,5 vCPU. El cambio de
  infraestructura es `2e78fc1` (`vmss_instances` = 2). Evidencia de la
  infraestructura en `evidencia/scaled/`.
- **Escenario:** el mismo que la ejecución final de 1 nodo. `baseline.yaml`,
  entorno `pool-ramp`: doce escalones de 60 s a 10, 25, 50, 75, 100, 150, 200,
  300, 400, 600, 800 y 1.000 rps, la mezcla del TP 1 y un pool compartido de
  conexiones keep-alive.
- **Generador de carga:** el mismo equipo y la misma red que el caso 1 nodo:
  Buenos Aires, ethernet cableada, latencia de base contra `/` con mediana de
  169 ms y p95 de 172,5 ms (`perf/results/baseline/root-tcorzo.json`).

Los números del caso 1 nodo vienen de su ejecución final, con tag
`measured/1-node-pool` (evidencia en `0cdcf5c`).

### Predicciones

| # | Métrica | Predicción | 1 nodo |
|---|---|---|---|
| C1 | ¿El throughput escala en proporción a los nodos? | No | — |
| C2 | Último escalón atendido completo (sin timeouts y con el 95 % de las respuestas) | 600 rps | 600 rps |
| C3 | Máximo de respuestas por segundo de los dos nodos juntos (Datadog, `arvault.http.responses`) | Menos de 750 | 648 |
| C4 | Componente que limita | Postgres, en la escritura sobre las cuentas internas | El mismo |
| C5 | Máximo de sesiones de Postgres esperando un lock (Azure Monitor, `sessions_by_wait_event_type`, `Lock`) | Más de 8 | 8 |
| C6 | CPU de Postgres en el escalón de 600 rps (Azure Monitor, `cpu_percent`) | 50 %, como con 1 nodo | 50,5 % |
| C7 | CPU de cada nodo en el escalón de 600 rps (Datadog, user + system) | 18 %, la mitad que con 1 nodo | 36,3 % |
| C8 | Parte de las respuestas que atiende cada nodo, en toda la ejecución | 50 %, con un margen de 5 puntos | — |
| C9 | Mediana en el cliente, escalones de 10 a 600 rps | 172,5 a 183,1 ms, como con 1 nodo | 172,5 a 183,1 ms |

### Razonamiento

- **C1 a C4.** Cada exchange aprobado actualiza dos filas: la cuenta interna
  de cada moneda (`UPDATE accounts … WHERE currency = $1`). Postgres atiende
  esas actualizaciones de a una por fila. Con 1 nodo, el límite fue de unas
  650 respuestas por segundo. A ese ritmo llegan unos 130 exchanges aprobados
  por segundo: el 40 % de los requests son exchanges, y ARCA aprueba cerca de
  la mitad. Un segundo nodo no acelera esas actualizaciones. A 800 rps llegan
  unos 160 exchanges aprobados por segundo, más de lo que las filas
  atendieron con 1 nodo. La cola crece y el escalón no se completa.
- **C3.** El techo puede subir un poco. Cada nodo tiene su propio pool de 10
  conexiones (`pg.Pool`, sin `max`). Con 1 nodo, las actualizaciones que
  esperaban el lock ocuparon hasta 8 de las 10 conexiones. Las lecturas se
  quedaron sin conexión: `GET /rates` pasó de 3 a 642 ms en el servidor. Con 2
  nodos hay 20 conexiones. Las lecturas tardan más en quedarse sin conexión,
  pero los exchanges siguen limitados por las mismas filas. Por eso esperamos
  menos de 750 respuestas por segundo, y no 1.300.
- **C5.** Con 20 conexiones, más actualizaciones pueden esperar el mismo lock a
  la vez. La espera crece, pero el throughput no. Postgres acepta 50
  conexiones, así que 20 no llegan al límite.
- **C6.** A igual carga, Postgres hace el mismo trabajo, venga de uno o de dos
  nodos. Con 1 nodo usó el 50,5 % de CPU a 600 rps.
- **C7.** El nodo no fue el límite: llegó al 36,3 % de CPU a 600 rps, y al
  45,4 % como máximo. Con dos nodos, cada uno atiende la mitad de los
  requests.
- **C8.** El load balancer reparte las conexiones entre los nodos. Con un pool
  keep-alive, reparte conexiones y no requests. En los escalones bajos hay
  pocas conexiones, y el reparto puede desviarse. Por eso lo medimos sobre la
  ejecución entera.
- **C9.** Hasta 600 rps, el servicio respondió en pocos milisegundos, y la
  mediana en el cliente fue casi toda latencia de base. Un segundo nodo no
  cambia eso.

### Qué cambiaría la predicción

- **Si el límite de 1 nodo fue el pool de 10 conexiones y no las filas,** 2
  nodos completan el escalón de 800 rps y atienden más de 750 respuestas por
  segundo. Las esperas por lock quedan bajas. Entonces C2, C3 y C5 fallan, y
  el límite real era el pool.
- **Si Postgres se queda sin CPU antes,** el techo baja. Con 1 nodo, su CPU
  siguió subiendo hasta el 84,5 % después del quiebre, sin más throughput.
- **Si Postgres se queda sin créditos de CPU,** Azure lo limita y el quiebre
  baja de 600 rps. B1ms es burstable. La ejecución de 1 nodo bajó los créditos
  de 32 a 30, así que una ejecución igual no debería agotarlos.

## Tácticas

### Terminación TLS (H-38)

**Hipótesis:** terminar TLS en el proceso de Node no cambia la latencia que
mide Artillery ni el componente que limita. Su costo aparece en la CPU de los
nodos, que sube en los dos, más en el que atiende más requests, sin
acercarse a saturarlos.

- **Caso:** 2 nodos del VMSS (`Standard_F1als_v7`, 1 vCPU cada uno), con un
  proceso de Node en pm2 por nodo que termina TLS con `node:https` en el 3443 y
  responde `308` a HTTPS en el 3080. El load balancer reenvía TCP 443 → 3443 y
  80 → 3080. Certificado autofirmado ECDSA P-256. Postgres `B_Standard_B1ms` y
  ARCA en ACI con 0,5 vCPU, como en el caso escalado. Los cambios son
  `898a868` a `4235673`; `vmss_instances` sigue en 2 (`2e78fc1`). Evidencia de
  la infraestructura en `evidencia/tls-termination/`.
- **Escenario:** el mismo que el caso escalado. `baseline.yaml`, entorno
  `pool-ramp`: doce escalones de 60 s a 10, 25, 50, 75, 100, 150, 200, 300,
  400, 600, 800 y 1.000 rps, la mezcla del TP 1 y un pool compartido de
  conexiones keep-alive. Lo único que cambia es el esquema de la URL, de
  `http://` a `https://`.
- **Generador de carga:** otro equipo que el del caso escalado: una laptop en
  Buenos Aires, con WSL2 sobre Windows, por WiFi (enlace de 585 Mbps, 88 y
  96 Mbit/s de bajada; `evidencia/entorno/matias/`). Su latencia de base contra
  `/`, ya por HTTPS, tiene mediana de 194,4 ms y p95 de 202,4 ms, con un rango
  de 188 a 207 ms (`perf/results/baseline/root-matias.json`). La del caso
  escalado, desde la estación cableada, tiene mediana de 169 ms y un rango de
  11 ms (`perf/results/baseline/root-tcorzo.json`). Las latencias en el
  cliente se comparan restando la latencia de base de cada equipo. La CPU de
  los nodos se mide en el servidor y no depende del generador.

Los números del caso escalado vienen de su ejecución, con tag
`measured/scaled`, tal como los resume el informe (sección *Caso escalado*).

#### Predicciones

| # | Métrica | Predicción | Escalado |
|---|---|---|---|
| T1 | Mediana en el cliente de cada escalón, de 10 a 400 rps, menos la latencia de base de su generador | La del mismo escalón del caso escalado, con una diferencia menor que los 19 ms de ruido de esta red: medianas de 198 a 205 ms | 3,5 a 10,5 ms sobre la base (172,5 a 179,5 ms) |
| T2 | Último escalón atendido completo (sin timeouts y con el 95 % de las respuestas) | 400 rps | 400 rps |
| T3 | Componente que limita | Postgres, en la escritura sobre las cuentas internas | El mismo |
| T4 | CPU de cada nodo en el escalón de 400 rps (Datadog, user + system) | Sube, a unos 13,5 % el menos cargado y 20 % el más cargado | 11,3 % y 15,6 % |
| T5 | CPU máxima de los nodos en la ejecución (Datadog, user + system) | Sube, entre 22,9 % y 30 % | 22,9 % |
| T6 | Diferencia de CPU entre los dos nodos en el escalón de 400 rps | Crece, a unos 7 puntos (entre 6 y 8) | 4,3 puntos |

#### Razonamiento

- **T1.** TLS tiene dos fases. El handshake, con criptografía asimétrica, pasa
  una vez por conexión. Después, cada request y cada respuesta se cifran con
  AES-256-GCM, que cuesta microsegundos por mensaje. `http.response_time` de
  Artillery es la fase `firstByte`, medida con la conexión ya abierta, así que
  no incluye el handshake (TP 1, `encrypt-data.typ`, citando
  `artillery/core/lib/engine_http.js:825`). Además, `pool-ramp` reutiliza las
  conexiones (`http.pool: 1000`): hay pocos handshakes. El cifrado por mensaje
  queda muy por debajo del ruido. La red cambia: este generador está 25 ms más
  lejos que el del caso escalado y varía 19 ms en lugar de 11. Por eso T1
  compara lo que la mediana suma sobre la latencia de base de cada equipo.
- **T2 y T3.** Los nodos no fueron el límite del caso escalado: llegaron como
  máximo al 22,9 % de CPU, y el límite fue Postgres, con 63 % de CPU a 600 rps
  y hasta 12 esperas por lock. TLS no cambia el trabajo de Postgres.
- **T4 y T5.** Cada request cuesta un poco más: el cifrado corre en el hilo del
  event loop de Node, sobre la única vCPU de cada nodo, el mismo que atiende
  los requests. Suman CPU los handshakes de las conexiones que abre el pool al
  subir la concurrencia de cada escalón, y el cifrado y descifrado de cada
  mensaje. A la misma carga, los mismos requests cuestan más CPU. Cada
  operación es barata, y cada nodo atiende la mitad de los requests, así que
  esperamos una subida chica: en T4, unos 2 puntos en el nodo menos cargado y
  4 en el más cargado, un 28 % más. La CPU máxima se da donde los nodos
  atienden más requests, y ese techo lo pone Postgres. Si el techo no cambia
  (T3), los nodos llegan al mismo throughput máximo con más trabajo por
  request. En T5 esperamos la misma proporción que en el nodo más cargado:
  22,9 % más un 28 % es unos 29 %, así que la máxima queda por debajo del
  30 %.
- **T6.** Los dos nodos terminan TLS, pero el costo de TLS es por request, no
  por nodo. Los dos no atienden la misma cantidad de requests en cada escalón:
  el load balancer reparte conexiones, y con el pool cada conexión lleva
  muchos requests. El nodo que atiende más paga más TLS, así que la diferencia
  entre los dos se estira.

#### Qué cambiaría la predicción

- **Si la CPU de los nodos sube más de lo previsto,** el costo de TLS en Node
  es mayor que el de la criptografía sola: llamadas al sistema y copias de
  buffers por cada mensaje. Fallan T4 y T5.
- **Si la CPU de un nodo llega al 100 % antes de los 400 rps,** el límite pasa
  a los nodos. Fallan T2 y T3, y la táctica sí cuesta throughput.
- **Si la diferencia entre nodos no crece, o pasa de 8 puntos,** el load
  balancer repartió distinto las conexiones del pool. Reparte conexiones y no
  requests, y con pocas conexiones el reparto de un escalón puede desviarse,
  con o sin TLS. Falla T6 sin que TLS sea la causa; lo verificamos con las
  respuestas por nodo (`datadog-http-responses-by-host`).
- **Si la mediana, menos la latencia de base, se mueve más de 19 ms,** el
  cifrado por mensaje no es despreciable, o la red cambió entre la latencia de
  base y la ejecución. Hay que medir de nuevo la latencia de base para separar
  las dos causas.
- **Si el generador se satura antes de los 400 rps,** la latencia y los
  timeouts miden el generador y no el servicio. Lo verificamos con
  `generador-vmstat.txt`. El del caso escalado usó toda su CPU recién desde
  600 rps.

### Tope de conexiones a Postgres

**Hipótesis:** con 2 nodos, el límite es la CPU de Postgres, y crece con la
cantidad de transacciones simultáneas sobre las cuentas internas. Con un tope
de 5 conexiones por nodo, Postgres recibe las mismas 10 transacciones
simultáneas que en el caso 1 nodo. Entonces trabaja como con 1 nodo: menos
CPU por respuesta, menos esperas por lock y más throughput sostenido que la
base.

- **Caso:** 2 nodos del VMSS (`Standard_F1als_v7`, 1 vCPU cada uno), con TLS
  en el proceso de Node, como la base. Lo único que cambia es `db_pool_max`,
  de 10 a 5 conexiones por nodo (`9d11baa`). `472e6aa` lo hizo configurable
  sin cambiar su valor. Postgres `B_Standard_B1ms` y ARCA en ACI con
  0,5 vCPU. Evidencia de la infraestructura en `evidencia/db-pool-cap/`.
- **Base:** la ejecución de la táctica TLS, con 2 nodos y 10 conexiones por
  nodo (`perf/results/tls-termination/2026-11-16/pool-ramp.json`). La columna
  *1 nodo* es la ejecución final de 1 nodo (`measured/1-node-pool`), con 10
  conexiones en total.
- **Escenario:** el mismo que la base. `baseline.yaml`, entorno `pool-ramp`:
  doce escalones de 60 s a 10, 25, 50, 75, 100, 150, 200, 300, 400, 600, 800
  y 1.000 rps, la mezcla del TP 1 y un pool compartido de conexiones
  keep-alive, sobre `https://`.
- **Generador de carga:** la estación cableada del caso escalado, no la
  laptop de la base. La base no se repitió desde esta estación. Su latencia
  de base contra `/`, por HTTPS, tiene mediana de 169 ms, p95 de 172,5 ms y
  un rango de 162 a 177 ms (`perf/results/baseline/root-tcorzo-https.json`).
  La de la base tiene mediana de 194,4 ms. Las latencias en el cliente se
  comparan restando la latencia de base de cada generador, como en T1. Las
  métricas de Postgres y de los nodos se miden en el servidor y no dependen
  del generador.

Método de las métricas por escalón: los 60 s de cada escalón salen del
reporte de Artillery (el primer intervalo marca el inicio del escalón de
10 rps). Respuestas por segundo: Datadog, `arvault.http.responses` de los dos
nodos, promedio de los 40 s centrales. p50 en el servidor: mediana de los p50
de 10 s de Datadog dentro del escalón. CPU de Postgres: Azure Monitor,
promedio del minuto que más se superpone con el escalón.

#### Predicciones

| # | Métrica | Predicción | Base | 1 nodo |
|---|---|---|---|---|
| D1 | ¿El throughput sostenido mejora respecto de la base? | Sí | — | — |
| D2 | Respuestas por segundo en el escalón de 800 rps | Entre 640 y 700 | 572,8 | 673,9 |
| D3 | Último escalón atendido completo (sin timeouts y con el 95 % de las respuestas) | 600 rps; el de 800 rps no se completa | 600 rps | 600 rps |
| D4 | Mediana en el cliente de cada intervalo de 10 s del escalón de 600 rps, menos la latencia de base de su generador | Menos de 20 ms: medianas de 169 a 189 ms | −3 a 439 ms (191 a 633 ms) | 11 a 14 ms (180 a 183 ms) |
| D5 | CPU de Postgres en el escalón de 600 rps (Azure Monitor, `cpu_percent`) | 50 %, con un margen de 5 puntos | 65,7 % | 50,5 % |
| D6 | CPU de Postgres por respuesta en el escalón de 600 rps (D5 dividido las respuestas por segundo) | 0,84 ms, con un margen de 0,1 ms | 1,11 ms | 0,84 ms |
| D7 | Máximo de sesiones de Postgres esperando un lock (Azure Monitor, `sessions_by_wait_event_type`, `Lock`) | 8 o menos | 16 | 8 |
| D8 | Máximo de conexiones activas en Postgres (Azure Monitor, `active_connections`) | 19, con un margen de 1 | 28 | 19 |
| D9 | p50 de `GET /rates` en el servidor, escalón de 600 rps (Datadog) | Menos de 10 ms | 261,4 ms | 2,6 ms |
| D10 | Componente que limita | Postgres, por CPU, desde 800 rps | Postgres | Postgres |

Los valores de las columnas *Base* y *1 nodo* salen de los archivos crudos
con el método de arriba. Para la base, del reporte de Artillery y de
`evidencia/tls-termination/2026-11-16/`. Para 1 nodo, de
`perf/results/1-node/2026-11-15/` y `evidencia/1-node/2026-11-15/`.

#### Razonamiento

- **D1, D2, D5 y D6.** A igual carga, Postgres usó más CPU con 2 nodos que
  con 1: 65,7 % contra 50,5 % a 600 rps, para casi las mismas respuestas por
  segundo (589,7 contra 599,5). Cada respuesta le costó 1,11 ms de CPU, contra
  0,84 ms. Del lado de Postgres, lo único que cambió fue la cantidad de
  conexiones, de 10 a 20. Cada exchange aprobado actualiza las dos mismas
  filas de `accounts`, ARS y USD. Con más transacciones simultáneas, más
  esperan el lock de esas filas. Interpretamos, como en la sección 8, que
  esas esperas le cuestan CPU a Postgres. Con 5 conexiones por nodo, la
  concurrencia vuelve a 10, y el costo por respuesta vuelve al de 1 nodo. Con
  menos CPU por respuesta, Postgres atiende más antes de saturarse: el
  throughput del escalón de 800 rps vuelve a las 673,9 respuestas por segundo
  de 1 nodo.
- **D3.** 1 nodo tampoco completó el escalón de 800 rps: el límite sigue en
  Postgres. El tope baja el costo por respuesta, pero no alcanza para
  atender 800.
- **D4.** Con 1 nodo, la mediana del escalón de 600 rps quedó entre 11 y
  14 ms sobre la latencia de base. Con la base, Postgres ya estaba saturado a
  600 rps, y la mediana subió hasta 439 ms sobre la latencia de base. Con el
  costo de 1 nodo, Postgres no se satura a 600 rps.
- **D7 y D8.** La suma de los pools acota las transacciones simultáneas. Con 1
  nodo, Postgres tuvo 19 conexiones activas con un pool de 10. Con 2 nodos,
  28 con dos pools de 10. Unas 9 conexiones no salen de los pools de la app.
  Con dos pools de 5, esperamos 10 de la app más esas 9. Con la misma
  concurrencia que 1 nodo, las esperas `Lock` vuelven a las 8 de 1 nodo.
- **D9.** La espera pasa de Postgres a Node. Un request que encuentra ocupadas
  las 5 conexiones de su nodo espera una libre dentro del proceso. Cada nodo
  atiende la mitad de los requests con la mitad de las conexiones: la misma
  proporción que 1 nodo con 10. Con 1 nodo, `GET /rates` tardó 2,6 ms en el
  servidor a 600 rps.
- **D10.** Los nodos no limitaron la base: llegaron como máximo al 51,1 % de
  CPU. ARCA no cambia. El tope no le agrega trabajo a Postgres por request.

`with-vmstat.sh` toma además las estadísticas acumuladas de Postgres antes y
después de la ejecución (`postgres-stats.txt`): transacciones, filas
actualizadas y fsyncs del WAL. La base no las tiene, así que sirven para
explicar el resultado, no para compararlo.

#### Qué cambiaría la predicción

- **Si la CPU de Postgres por respuesta no baja,** su costo extra con 2 nodos
  no viene de la concurrencia sobre las filas. Viene de algo que crece con los
  nodos y no con las conexiones. Fallan D1, D2, D5 y D6.
- **Si `GET /rates` tarda más en el servidor antes de que Postgres se sature,**
  el tope solo movió la cola a Node, sin acortarla. Fallan D4 y D9.
- **Si las métricas del servidor mejoran pero D4 no,** la diferencia viene del
  generador o de la red, no del servicio. Lo verificamos con
  `generador-vmstat.txt` y con la latencia de base de esta estación.
- **Si Postgres se queda sin créditos de CPU,** Azure lo limita y el
  throughput baja por eso y no por el tope. Lo verificamos con
  `postgres-cpu-credits-remaining.json`.

### Base del tope de conexiones: TLS desde la estación cableada

**Hipótesis:** la configuración de la táctica TLS, medida desde la estación
cableada, se comporta como el caso escalado medido desde esa misma estación.
TLS no cambia el trabajo de Postgres (T3), y el generador es el del caso
escalado. Postgres limita por CPU, con más esperas por lock que con 1 nodo.

Esta ejecución reemplaza a la de la táctica TLS como base del tope de
conexiones. Aquella corrió desde otro generador, y la táctica corre desde
esta estación: así las dos ejecuciones comparadas difieren solo en
`db_pool_max`.

- **Caso:** la configuración de la táctica TLS. 2 nodos del VMSS
  (`Standard_F1als_v7`, 1 vCPU cada uno), TLS en el proceso de Node,
  10 conexiones a Postgres por nodo (`9431c65`). Postgres `B_Standard_B1ms` y
  ARCA en ACI con 0,5 vCPU. Evidencia de la infraestructura en
  `evidencia/db-pool-cap/`.
- **Escenario:** el de la táctica TLS. `baseline.yaml`, entorno `pool-ramp`,
  sobre `https://`.
- **Generador de carga:** la estación cableada del caso escalado. Latencia de
  base contra `/` por HTTPS: mediana de 169 ms, p95 de 172,5 ms, rango de 162
  a 177 ms (`perf/results/baseline/root-tcorzo-https.json`).

Método: el de la sección anterior, con una precisión. La CPU de Postgres de un
escalón es el mayor promedio por minuto entre los minutos de Azure Monitor
que se superponen con él. En el caso escalado, el escalón de 600 rps cae
mitad en un minuto y mitad en el siguiente, y esta regla da el 63,0 % del
informe.

#### Predicciones

| # | Métrica | Predicción | Escalado (esta estación, sin TLS) | TLS (otra estación) |
|---|---|---|---|---|
| B1 | CPU de Postgres en el escalón de 600 rps | 65 %, con un margen de 5 puntos | 63,0 % | 65,7 % |
| B2 | CPU de Postgres por respuesta en el escalón de 600 rps | 1,1 ms, con un margen de 0,1 ms | 1,08 ms | 1,11 ms |
| B3 | Máximo de sesiones de Postgres esperando un lock (`Lock`) | Entre 12 y 16 | 12 | 16 |
| B4 | Máximo de conexiones activas en Postgres | 28, con un margen de 1 | 28 | 28 |
| B5 | Respuestas por segundo en el escalón de 800 rps | Entre 540 y 600 | 540,5 | 572,8 |
| B6 | Último escalón atendido completo (sin timeouts y con el 95 % de las respuestas) | 400 rps | 400 rps | 600 rps |
| B7 | p50 de `GET /rates` en el servidor, escalón de 600 rps | Más de 100 ms | 165,3 ms | 261,4 ms |
| B8 | Mediana en el cliente de cada intervalo de 10 s, escalones de 10 a 400 rps | 169 a 190 ms: menos de 21 ms sobre la latencia de base | 172 a 180 ms | 180 a 416 ms, sobre 194,4 ms |
| B9 | Componente que limita | Postgres, por CPU | Postgres | Postgres |

#### Razonamiento

- **B1 a B5 y B9.** Del lado de Postgres, esta ejecución es igual al caso
  escalado: 2 nodos con 10 conexiones cada uno, la misma mezcla y las mismas
  filas de `accounts`. La ejecución TLS confirmó que TLS no le agrega trabajo
  a Postgres: 1,11 ms de CPU por respuesta, contra 1,08 ms sin TLS. Las dos
  ejecuciones anteriores marcan el rango de B3 y B5.
- **B6.** El escalón de 600 rps está en el borde. Desde esta estación, el
  caso escalado no lo completó: tuvo timeouts desde los 20 s. Desde la otra
  estación, la ejecución TLS lo completó, con la mediana hasta 633 ms. El
  generador es el del caso escalado, así que esperamos su resultado.
- **B7.** A 600 rps, Postgres está saturado en las dos ejecuciones
  anteriores, y los requests esperan conexión. `GET /rates` pasa de unos
  2 ms a más de 100 ms en el servidor.
- **B8.** Hasta 400 rps, el servicio responde en pocos milisegundos, y la
  mediana es casi toda latencia de base. La latencia de base de esta
  estación es la misma con HTTPS que sin él. El caso escalado quedó entre 3,5
  y 10,5 ms sobre ella. El margen suma el rango de 15 ms de la latencia de
  base.

#### Qué cambiaría la predicción

- **Si la CPU por respuesta queda cerca de 0,84 ms,** el costo extra de las
  ejecuciones anteriores con 2 nodos no se repite. Entonces el tope de
  conexiones no tiene nada que corregir, y su predicción D cambia.
- **Si completa el escalón de 600 rps,** el resultado de B6 depende de la
  ejecución y no del generador: el borde está justo en 600 rps. Comparamos
  la táctica con las métricas del servidor, que no tienen ese borde.
- **Si el generador se satura antes de los 600 rps,** la ejecución mide el
  generador. Lo verificamos con `generador-vmstat.txt`.
