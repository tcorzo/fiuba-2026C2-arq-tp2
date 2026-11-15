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
