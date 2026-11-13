#import "../plantilla.typ": *

= Entorno

== Región

Todos los recursos corren en `centralus` [E-17]. No usamos la región que
recomienda la cátedra, porque ahí la suscripción no puede crear Postgres
(@descartada-region). El load balancer, el VMSS, Postgres y ARCA comparten la
región, así que el tráfico entre ellos no cruza regiones.

== Generador de carga

#pendiente[
  Ubicación del generador de carga, tipo de conexión a internet y ancho de
  banda disponible. Todas las pruebas que se comparan entre sí corren desde la
  misma ubicación.
]

== Latencia de red de base

#pendiente[
  Medición contra `/`, sin carga y sin pasar por ARCA ni Postgres, antes de las
  pruebas. Requiere el stack `platform` desplegado.
]
