#import "../plantilla.typ": *

= Entorno

== Región

Todos los recursos corren en `centralus` [E-17]. No usamos la región que
recomienda la cátedra, porque ahí la suscripción no puede crear Postgres
(@descartada-region). El load balancer, el VMSS, Postgres y ARCA comparten la
región, así que el tráfico entre ellos no cruza regiones.

== Generador de carga

Artillery corre en un equipo en Buenos Aires, fuera de Azure. El equipo se
conecta por WiFi, con el puerto ethernet desconectado [E-67]. El enlace es de
5 GHz y negocia 1170 Mbit/s con una señal del 70 % [E-68].

El ancho de banda disponible, medido con `speedtest-cli`, es de 66 Mbit/s de
bajada y 46 Mbit/s de subida [E-69]. Todas las pruebas que comparamos corren
desde este equipo y esta red.

== Latencia de red de base

Medimos la latencia de base el 12 de noviembre, antes de las pruebas de carga
[E-70]. Artillery mandó un `GET /` por segundo durante 60 s a través del load
balancer, que tenía un solo nodo detrás [E-71] [E-73].

El handler de `/` devuelve un texto fijo, sin consultar Postgres ni llamar a
ARCA [E-72]. La medición cubre internet, el load balancer y Express en el nodo,
pero no la lógica del servicio.

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

Entre el mínimo y el máximo hay 16 ms [E-70]. Tomamos como ruido una diferencia
menor entre dos ejecuciones.

Toda latencia de las secciones siguientes incluye estos 180 ms. Para estimar el
tiempo dentro de Azure, le restamos la mediana de base a la mediana medida.
