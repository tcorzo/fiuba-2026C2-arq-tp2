#import "../plantilla.typ": *

= Integración con ARCA

== Qué responde ARCA

Antes de integrarlo, llamamos a `POST /validar` desde el jumpbox con 200 DNIs
aleatorios. ARCA respondió 102 aprobaciones, 50 rechazos y 48 errores `500`
[E-45]. Las aprobaciones tardaron una mediana de 371 ms y los rechazos, 374 ms.
Los `500` llegaron en 2 ms, con el body vacío [E-45].

Repetimos tres DNIs 15 veces cada uno. La aprobación o el rechazo es fijo para
cada DNI. El `500` no: apareció en 4, 6 y 7 de las 15 llamadas [E-46]. Un
rechazo es una respuesta de negocio; un `500` es una falla al azar del mock.

== Implementación

`POST /exchange` recibe un campo `dni` obligatorio, de tipo texto. El servicio
lo valida antes de llamar a ARCA: siete u ocho dígitos, sin cero adelante, entre
1000000 y 99999999 [E-47] [E-48]. Un `dni` inválido responde `400` y no llega a
ARCA [E-50] [E-53].

El adaptador llama a `POST {arcaUri}/validar` con `{"dni": …}`. Usa `fetch` de
Node con una sola señal de timeout para toda la llamada [E-49]. El timeout es de
2000 ms y llega a la app por el output `app_config` de Terraform [E-51]. Es
cuatro veces la respuesta más lenta que observamos [E-45].

El servicio valida el `dni` antes de cualquier escritura o transferencia
[E-52]. Así, un rechazo o una falla de ARCA no mueve fondos ni escribe en el
log. Los tests lo verifican para el rechazo, la falla y cualquier otro error
del adaptador [E-53]. Un exchange aprobado devuelve el `codigoAutorizacion` de
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

El rechazo es un `403`: el pedido es válido, pero ARCA no autoriza al cliente.
Una falla de ARCA es un `502`: el error es de la dependencia, no del cliente
[E-55]. Así, un cliente y un dashboard distinguen las dos situaciones.

El servicio no reintenta. Una falla de ARCA responde `502` en el primer intento
[E-49]. Lo decidimos así para medir la tasa de fallas de ARCA tal como es. El
reintento es una candidata a táctica superadora (sección 9).

== Log

Cada validación escribe una línea en el log: el resultado y, si ARCA aprueba, el
código de autorización [E-57]. Este es el log completo de ARCA en el nodo,
después de 15 requests a través del load balancer [E-56]:

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

Son 14 líneas para 15 requests: el `dni` inválido no llegó a ARCA [E-50]. Hubo
4 aprobaciones, 4 rechazos y 6 errores `500` de ARCA [E-56].

== Métricas propias

#pendiente[
  Las métricas `arca.validation.duration` y `arca.validation.outcomes`, con un
  screenshot de Datadog durante la medición de 1 nodo. Depende del PR \#18: hasta
  ese cambio, las métricas de la app no llegaban al agente de Datadog.
]
