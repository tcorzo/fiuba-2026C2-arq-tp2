#import "../plantilla.typ": *

= Integración con ARCA

== Qué responde ARCA

Antes de integrarlo, llamamos a `POST /validar` desde el jumpbox con 200 DNIs
aleatorios. ARCA respondió 102 aprobaciones, 50 rechazos y 48 errores `500`
[E-45]. Las aprobaciones tardaron una mediana de 371 ms y los rechazos, 374 ms.
Los `500` llegaron en 2 ms, con el body vacío [E-45].

Mandamos tres DNIs 15 veces cada uno. La aprobación o el rechazo es fijo para
cada DNI, pero el `500` no: apareció en 4, 6 y 7 de las 15 llamadas [E-46]. Un
rechazo es una respuesta de negocio; un `500` es una falla al azar del mock.

== Implementación

`POST /exchange` recibe un campo `dni` obligatorio, de tipo texto. El servicio
lo valida antes de llamar a ARCA: debe tener siete u ocho dígitos, sin
cero adelante [E-47] [E-48]. Un `dni` inválido responde `400` y no llega a
ARCA [E-50] [E-53].

El generador de carga manda un `dni` válido y aleatorio en cada exchange
[E-77]. Lo manda como texto: corrimos el escenario contra un servidor local que
imprime el body, y los 12 exchanges llegaron con el `dni` entre comillas [E-78].

El adaptador llama a `POST {arcaUri}/validar` con `{"dni": …}`. Usa `fetch` de
Node con una sola señal de timeout para toda la llamada [E-49]. El timeout es de
2.000 ms y llega a la app por el output `app_config` de Terraform [E-51]. Es
cuatro veces la respuesta más lenta que observamos [E-45].

El servicio valida el `dni` antes de cualquier escritura o transferencia
[E-52]. Un rechazo o una falla de ARCA no mueve fondos ni agrega una entrada al
log de exchanges. Los tests lo verifican para cada error del adaptador [E-53]. Un exchange aprobado devuelve el `codigoAutorizacion` de
ARCA en la respuesta [E-50].

== Manejo de errores

#table(
  columns: (1fr, auto, auto),
  inset: (x: 6pt, y: 4pt),
  stroke: 0.4pt + suave,
  align: (left, left, left),
  table.header([*Caso*], [*Respuesta*], [*Evidencia*]),
  [`dni` ausente, no texto o fuera de rango],
  [`400 VALIDATION_ERROR`],
  [\[E-50\] \[E-53\]],

  [ARCA aprueba], [`200` con `codigoAutorizacion`], [\[E-50\]],
  [ARCA rechaza], [`403 ARCA_REJECTED`], [\[E-54\]],
  [ARCA responde `500` u otro status],
  [`502 ARCA_UNAVAILABLE`],
  [\[E-50\] \[E-53\]],

  [ARCA no responde dentro del timeout], [`502 ARCA_UNAVAILABLE`], [\[E-53\]],
  [El body no tiene un `ok` booleano], [`502 ARCA_UNAVAILABLE`], [\[E-53\]],
  [ARCA no es alcanzable], [`502 ARCA_UNAVAILABLE`], [\[E-53\]],
)

El rechazo es un `403`: el request es válido, pero ARCA no autoriza al cliente.
Una falla de ARCA es un `502`: el error es de la dependencia, no del cliente
[E-55]. Con esos dos códigos, un cliente y un dashboard distinguen las dos
situaciones.

El servicio no reintenta: una falla de ARCA responde `502` en el primer intento
[E-49]. Lo decidimos para que un reintento no oculte la tasa de fallas de ARCA.

== Log

Cada validación escribe una línea en el log: el resultado y, si ARCA aprueba, el
código de autorización [E-57]. Estas son todas las líneas de ARCA en el log
del nodo, después de 15 requests a través del load balancer [E-56]:

```text
arca.validation error reason=status_500
arca.validation error reason=status_500
arca.validation error reason=status_500
arca.validation approved codigoAutorizacion=176889c2-519f-415f-86f9-4e2f08c9d6fc
arca.validation approved codigoAutorizacion=fd23f549-1295-4cc4-a1e5-ce4569e4c7a2
arca.validation error reason=status_500
arca.validation error reason=status_500
arca.validation approved codigoAutorizacion=57af9eaf-5009-42ee-a6e6-9363fef51e21
arca.validation error reason=status_500
arca.validation approved codigoAutorizacion=5a0b142c-a79e-4bac-b19d-6158809a2d5e
arca.validation rejected
arca.validation rejected
arca.validation rejected
arca.validation rejected
```

Son 14 líneas para 15 requests, porque el `dni` inválido no llegó a ARCA
[E-50].

== Métricas propias

La misma función que escribe la línea de log publica dos métricas por cada
validación, con cualquier resultado [E-79] [E-80]:

#table(
  columns: (auto, auto, 1fr),
  inset: (x: 6pt, y: 4pt),
  stroke: 0.4pt + suave,
  align: (left, left, left),
  table.header([*Métrica*], [*Tipo*], [*Qué mide*]),
  [`arvault.arca.validation.duration`],
  [Distribución (ms)],
  [La duración de cada llamada a `POST /validar`],

  [`arvault.arca.validation.outcomes`],
  [Contador],
  [Las validaciones, con el tag `outcome`: `approved`, `rejected` o `error`],
)

La duración es una distribución y no un timer, para que Datadog calcule sus
percentiles con las muestras de todos los nodos. En el caso escalado, eso evita
promediar percentiles de dos nodos [E-81].

El exchange publica su propia duración, `arvault.exchange.processing.duration`,
para correlacionar ARCA con arVault. Empieza a medir cuando termina la
validación, así que las dos duraciones no se superponen [E-82]. El dashboard
muestra las dos en un mismo gráfico, y las validaciones por resultado en otro
[E-83].

== ARCA bajo carga

En la ejecución final del caso de 1 nodo, el p50 de la validación quedó entre
291 y 310 ms desde 75 hasta 1.000 rps [E-119]. De 10 a 50 rps, con menos
validaciones por intervalo, varió entre 265 y 346 ms.

El p50 de `exchange.processing` se mantuvo entre 320 y 403 ms hasta 600 rps
[E-120]. En cada intervalo de 10 s de esos
escalones, el p50 de ARCA fue entre el 42 y el 49 % de la suma de los dos p50.

A 800 y 1.000 rps, `exchange.processing` llegó a 5.051 ms y ARCA siguió igual,
con un máximo de 69 de sus 500 milicores [E-124]. El límite estuvo en Postgres
(sección 7). El screenshot del dashboard muestra los dos gráficos durante la
ejecución [E-128].

Contamos los resultados con los códigos que recibió el generador de carga
[E-114]. En cada escalón, los exchanges respondidos fueron entre 46 y 50 %
aprobados (`200`), entre 23 y 27 % rechazados (`403`) y entre 24 y 31 % errores
de ARCA (`502`). En toda la ejecución fueron 48,9 %, 26,0 % y 25,1 %, cerca de
la proporción que dio ARCA sin carga [E-45]. Los timeouts de 800 y 1.000 rps no
tienen respuesta y quedan fuera de esa cuenta.
