#import "../plantilla.typ": *

= Caso 1 nodo

El caso corre sobre una sola instancia `Standard_F1als_v7` del VMSS [E-111], con
un proceso de Node [E-61]. Detrás están Postgres `B_Standard_B1ms` [E-04] y ARCA
con 0,5 vCPU [E-59]. La ejecución que analizamos corrió sobre el tag
#commit("measured/1-node-pool").

El generador de carga es un equipo en Buenos Aires, conectado por ethernet
cableada a 1.000 Mb/s [E-89]. Desde ese equipo, la latencia de base contra `/`
tiene una mediana de 169 ms y un p95 de 172,5 ms [E-90].

Las predicciones están en `perf/predicciones.md` [E-88]. Las predicciones del
caso son P1 a P9, que commiteamos en #sha("f78658e") antes de medir nada.

== Escenario

Repetimos la rampa de la ejecución final del TP 1 y la extendimos hasta
1.000 rps: escalones de 60 s a 10, 25, 50, 75, 100, 150, 200, 300, 400, 600, 800
y 1.000 rps [E-92]. La mezcla es 40 % `POST /exchange`, 30 % `GET /rates`, 20 %
`GET /accounts` y 10 % `GET /log`. Cada exchange manda un `dni` aleatorio.

Cada usuario virtual manda un request, y las llegadas no esperan respuestas.
A diferencia del TP 1, los requests comparten conexiones keep-alive
(`http.pool`), por la razón que explica la sección siguiente. Los `403` y `502` que
devuelve el nodo trasladan la respuesta de ARCA (sección 6), así que no los
contamos como fallas del nodo.

== Cómo llegamos a esta ejecución

La primera ejecución usó la rampa del TP 1 sin cambios, con una conexión nueva
por request. Desde 200 rps, 24.652 de 30.000 requests terminaron en timeout
[E-84], pero el nodo no recibió esas conexiones [E-85]. El generador resolvía el
nombre del load balancer por DNS a 134 resoluciones por segundo [E-86].

Con el nombre en `/etc/hosts`, una rampa contra `/` pasó los 200 rps [E-87]. La
rampa tuvo 3.047 timeouts, casi todos a 300 rps, y el nodo abrió 35.991 conexiones para 35.953
respuestas [E-85] [E-110]. Desde este equipo, por encima de unas 200 conexiones
nuevas por segundo, los SYNs no llegan al nodo.

La segunda ejecución mandó 4 requests por conexión. Atendió hasta 600 rps y
empezó a quebrarse a los 20 s del último escalón, de 800 rps [E-94].
No mostró qué pasa por encima.

Con un pool compartido de conexiones, el generador mandó 114.000 requests contra
`/` hasta 1.000 rps, sin errores [E-112]. El nodo abrió 469 conexiones para todos
[E-113]. Con eso armamos la ejecución final.

== Resultados

La @tabla-pool resume cada escalón. Toma los cinco intervalos de 10 s que caen
enteros dentro de cada escalón de 60 s.

#figure(
  {
    set text(size: 8pt)
    table(
      columns: 9,
      inset: (x: 4pt, y: 3pt),
      stroke: 0.4pt + suave,
      align: right,
      table.header(
        [*rps*],
        [*Requests*],
        [*Respuestas*],
        [*Timeouts*],
        [*Mediana cliente (ms)*],
        [*p50 `/rates` servidor (ms)*],
        [*p50 exchange servidor (ms)*],
        [*Atendidos por segundo*],
        [*CPU nodo (%)*],
      ),
      [10], [500], [500], [0], [172,5--175,9], [1,5], [443], [10,0], [2,7],
      [25], [1.250], [1.254], [0], [172,5], [1,3], [487], [25,0], [3,5],
      [50], [2.500], [2.501], [0], [172,5], [1,2], [497], [50,0], [7,2],
      [75], [3.750], [3.751], [0], [175,9], [1,1], [498], [74,8], [8,8],
      [100], [5.000], [5.006], [0], [172,5], [1,1], [494], [99,9], [10,7],
      [150], [7.500], [7.492], [0], [175,9], [1,1], [494], [149,4], [14,5],
      [200], [10.000], [10.001], [0], [172,5], [1,0], [486], [199,5], [14,8],
      [300],
      [15.000],
      [14.992],
      [0],
      [175,9--179,5],
      [1,5],
      [494],
      [299,7],
      [16,8],

      [400],
      [20.000],
      [20.018],
      [0],
      [172,5--175,9],
      [1,1],
      [486],
      [400,2],
      [23,8],

      [600],
      [30.000],
      [29.993],
      [0],
      [179,5--183,1],
      [2,8],
      [526],
      [600,4],
      [36,3],

      [800],
      [40.002],
      [32.843],
      [4.708],
      [685,5--1.002,4],
      [642,5],
      [2.982],
      [647,6],
      [45,4],

      [1.000],
      [50.001],
      [30.550],
      [19.202],
      [837,3--982,6],
      [662,6],
      [5.952],
      [640,8],
      [42,4],
    )
  },
  caption: [Ejecución final por escalón. Cliente: rango de las medianas de cada
    intervalo de 10 s [E-114]. Servidor: mediana del p50 de Datadog por ruta
    [E-115]. Atendidos: respuestas del nodo por segundo, sin los 10 s de cada
    borde [E-116]. CPU del nodo, user + system: promedio [E-117].],
) <tabla-pool>

Hasta 600 rps, el nodo respondió cada escalón completo y sin timeouts [E-114].
La mediana en el cliente quedó entre 172,5 y 183,1 ms, la latencia de base más
el servicio. En el servidor, `GET /rates` tardó de 1 a 3 ms, y el exchange, unos
500 ms, sin tendencia con la carga [E-115].

=== Dónde se satura

El nodo atendió como máximo 674 requests por segundo, en el escalón de 800 rps
[E-116]. Al final de ese escalón atendía 591 por segundo, y en el de 1.000 rps,
de 602 a 665. Pasado ese punto, más carga no suma throughput: el sostenido es
600 rps.

La latencia en el servidor confirma la saturación. El p50 de `GET /rates` pasó de
3 a 643 ms, y el del exchange, de 526 a 2.982 ms [E-115] [E-128]. La
@tabla-componentes muestra los componentes que no limitaron.

#figure(
  table(
    columns: (auto, 1fr),
    inset: (x: 6pt, y: 4pt),
    stroke: 0.4pt + suave,
    align: (left, left),
    table.header([*Componente*], [*A 800 y 1.000 rps*]),
    [CPU del nodo], [47,4 % de máximo [E-117]],
    [Event loop], [lag máximo de 19,9 ms [E-118]],
    [ARCA],
    [p50 de hasta 310 ms [E-119], 69 de sus 500 milicores de máximo [E-124]],

    [Proceso de Node], [sin reinicios ni descartes de conexiones [E-131]],
  ),
  caption: [Componentes con capacidad libre en los escalones de 800 y 1.000
    rps.],
) <tabla-componentes>

El límite está en Postgres, en la escritura del exchange.
`exchange.processing`, que excluye a ARCA, subió su p50 de unos 360 ms a
4.393 ms [E-120]. La CPU de Postgres creció con cada escalón y llegó a 84,5 %
de promedio en un minuto [E-121].

Las esperas `Lock` aparecen ya entre los escalones de 75 y 100 rps, con 2, y
llegan a 8 entre los de 400 y 600 rps [E-122]. Un exchange que espera un lock
retiene su conexión del pool de 10 [E-62]. Interpretamos que, con Postgres más
cargado, cada transacción retiene el lock más tiempo, el pool se llena y las
lecturas esperan detrás.

Postgres es burstable y arrancó con 32 créditos de CPU, de los que la ejecución
gastó 2 [E-123]. No se agotaron, así que la CPU de Postgres no tuvo ese límite.

Pasada la saturación, parte de los timeouts son de la red. Con los sockets
ocupados, el pool abrió conexiones nuevas: el generador retransmitió 175.162
SYNs [E-126], y el nodo recibió sólo 4.356 conexiones [E-125]. Por eso medimos
el throughput con las respuestas del nodo y no con los timeouts del cliente.

El generador usó toda su CPU desde 600 rps [E-127]. No agregó demora:
`GET /rates` en el cliente menos su p50 en el servidor quedó entre 162 y 175 ms
en todos los escalones [E-114] [E-115], la latencia de base.

== Predicciones

#[#set par(justify: false)
  #grid(
    columns: (1fr, 1fr),
    gutter: 6pt,
    prediccion(
      metrica: [P1: mediana de `GET /rates` en el cliente, 10 a 100 rps],
      predicho: [171 ms],
      observado: [169 a 172,5 ms por intervalo de 10 s],
      evidencia: "E-114",
    ),
    prediccion(
      metrica: [P2: mediana de la validación con ARCA, 10 a 100 rps],
      predicho: [370 ms],
      observado: [282 a 308 ms (mediana de cada escalón)],
      evidencia: "E-119",
    ),

    prediccion(
      metrica: [P3: mediana de `exchange.processing`, 10 rps],
      predicho: [355 ms],
      observado: [353,7 ms],
      evidencia: "E-120",
    ),
    prediccion(
      metrica: [P4: p95 de `POST /exchange` en el cliente, 10 rps],
      predicho: [1.040 ms],
      observado: [1.002 a 1.023 ms por intervalo de 10 s],
      evidencia: "E-114",
    ),

    prediccion(
      metrica: [P5 y P6: `502` y `403`, hasta 150 rps],
      predicho: [24 % y 25 % de los exchanges],
      observado: [25,0 % y 25,8 % (2.054 y 2.122 de 8.213)],
      evidencia: "E-114",
    ),
    prediccion(
      metrica: [P7: último escalón completo],
      predicho: [150 rps],
      observado: [600 rps],
      evidencia: "E-114",
    ),

    prediccion(
      metrica: [P8: CPU del nodo a 150 rps],
      predicho: [menos del 50 %],
      observado: [14,5 % de promedio],
      evidencia: "E-117",
    ),
    prediccion(
      metrica: [P9: componente que limita],
      predicho: [Postgres, en la escritura del exchange],
      observado: [Postgres, en la escritura del exchange],
      evidencia: "E-120",
    ),
  )]

Acertamos P1, P3, P4, P5 y P6, que dependen del código, de ARCA y de la red, no
de la carga. ARCA respondió en unos 300 ms y no en los 371 ms del issue \#14,
medidos desde el jumpbox; no investigamos esa diferencia.

P9 acertó el componente, y P7 erró la capacidad por cuatro. P7 tomó el quiebre
del TP 1, después de 150 rps [E-130], y supuso que se compensaban dos efectos
del despliegue. No consideró la CPU de Postgres. En el TP 1, `db` tenía un límite
de 0,25 cores [E-129]; acá Postgres tiene un servidor propio [E-04], y usó el
84,5 % recién por encima de 600 rps [E-121].
