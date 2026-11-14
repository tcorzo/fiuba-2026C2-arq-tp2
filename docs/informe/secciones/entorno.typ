#import "../plantilla.typ": *

= Entorno

== Región

Todos los recursos corren en `centralus` [E-17]. No usamos la región que
recomienda la cátedra, porque ahí la suscripción no puede crear Postgres
(@descartada-region). El load balancer, el VMSS, Postgres y ARCA comparten la
región, así que el tráfico entre ellos no cruza regiones.

== Generador de carga

Artillery corre en un equipo en Buenos Aires, fuera de Azure. El equipo se
conecta a internet por WiFi. El puerto ethernet no está conectado [E-67].

El enlace WiFi usa la banda de 5 GHz (5300 MHz). Negocia 1170 Mbit/s con una
señal del 70 % [E-68]. `speedtest-cli` midió 66 Mbit/s de bajada y 46 Mbit/s
de subida [E-69].

Todas las pruebas que comparamos entre sí corren desde este mismo equipo y esta
misma red.

== Latencia de red de base

Medimos la latencia de base el 12 de noviembre, antes de las pruebas de carga y
sin otra carga sobre el sistema [E-70]. En ese momento había un nodo detrás del
load balancer [E-73]. Artillery mandó un `GET /` por segundo durante 60 s, a
través del load balancer [E-71].

El handler de `/` responde un texto fijo. No consulta Postgres ni llama a
ARCA [E-72]. Así, la medición incluye la red y el load balancer, pero no el
trabajo del servicio.

#table(
  columns: (auto, auto, auto, auto, auto, auto),
  inset: (x: 6pt, y: 4pt),
  stroke: 0.4pt + suave,
  align: right,
  table.header(
    [*Requests*], [*Errores*], [*Mínimo*], [*Mediana*], [*p95*], [*Máximo*]
  ),
  [60], [0], [171 ms], [179,5 ms], [183,1 ms], [187 ms],
)

Las 60 respuestas fueron `200` [E-70]. Entre el mínimo y el máximo hay 16 ms.
Una diferencia de latencia menor que ese rango entre dos ejecuciones la
tratamos como ruido.

Cada latencia de los casos siguientes incluye estos 180 ms aproximados. Para
estimar el tiempo dentro de Azure, restamos la mediana de base a la mediana
medida.
