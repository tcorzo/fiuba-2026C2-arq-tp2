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
  `55a2922`. Evidencia de la infraestructura en `evidencia/1-node/`.
- **Escenario:** `baseline.yaml`, entorno `ramp`: ocho escalones de 60 s a 10,
  25, 50, 75, 100, 150, 200 y 300 rps. Mezcla: 40 % `POST /exchange`, 30 %
  `GET /rates`, 20 % `GET /accounts` y 10 % `GET /log`. Es la misma rampa y la
  misma mezcla que la ejecución final del TP 1.
- **Generador de carga:** Buenos Aires, WiFi. Latencia de base contra `/`:
  mediana de 179,5 ms y p95 de 183,1 ms (`perf/results/baseline/root.json`).

### Predicciones

| # | Métrica | Predicción |
|---|---|---|
| P1 | Mediana de `GET /rates` en el cliente, escalones de 10 a 100 rps | 182 ms |
| P2 | Mediana de `arca.validation.duration` (Datadog), escalones de 10 a 100 rps | 370 ms |
| P3 | Mediana de `exchange.duration` (Datadog, sin ARCA), escalón de 10 rps | 355 ms |
| P4 | p95 de `POST /exchange` en el cliente, escalón de 10 rps | 1.050 ms |
| P5 | Respuestas `502 ARCA_UNAVAILABLE` antes del quiebre | 24 % de los exchanges, 10 % de todos los requests |
| P6 | Respuestas `403 ARCA_REJECTED` | 25 % de los exchanges, 10 % de todos los requests |
| P7 | Último escalón atendido completo (sin timeouts y con el 95 % de las respuestas) | 150 rps |
| P8 | CPU del nodo en el escalón de 150 rps | menos del 50 % |
| P9 | Componente que limita | Postgres, en el camino de escritura del exchange |

### Razonamiento

- **P1.** `GET /rates` no llama a ARCA. Hace una consulta a Postgres dentro de
  la misma región. En el TP 1 su mediana era de 1 ms en el servidor. Le sumamos
  la latencia de base, porque Artillery mide el `response_time` sin el
  connect. Ese tiempo coincide con un RTT.
- **P2.** ARCA respondió con una mediana de 371 ms en 200 llamadas desde el
  jumpbox (issue #14). Suponemos que esos 370 ms son espera y no CPU: con
  0,5 vCPU, ARCA tendría que atender varias llamadas a la vez sin demorarse más.
- **P3.** `exchange.duration` empieza después de la validación con ARCA. Mide
  lo mismo que en el TP 1: las dos transferencias concurrentes de 200 a 400 ms
  (H-12) más las consultas a Postgres. En la ejecución final del TP 1, la
  mediana del exchange a 10 rps fue de 354 ms.
- **P4.** Un exchange aprobado suma el RTT (unos 180 ms), ARCA (hasta 502 ms
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

## Tácticas
