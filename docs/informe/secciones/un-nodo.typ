#import "../plantilla.typ": *

= Caso 1 nodo

El caso corre sobre una sola instancia `Standard_F1als_v7` del VMSS [E-91], con
un proceso de Node [E-61]. Detrás están Postgres `B_Standard_B1ms` [E-04] y ARCA
con 0,5 vCPU [E-59]. Medimos dos veces, sin cambios en la infraestructura, sobre
los tags #commit("measured/1-node") y #commit("measured/1-node-sessions").

Las dos ejecuciones corren desde un equipo en Buenos Aires, conectado por
ethernet cableada a 1.000 Mb/s [E-89]. Desde ese equipo, la latencia de base
contra `/` tiene una mediana de 169 ms y un p95 de 172,5 ms [E-90].

Las predicciones están en `perf/predicciones.md` [E-88]. Commiteamos P1 a P9 en
#sha("f78658e"), antes de los resultados de #sha("ebf1f58"), y S1 a S6 en
#sha("b367b21"), antes de los de #sha("0913904").

== Escenarios

#table(
  columns: (auto, 1fr),
  inset: (x: 6pt, y: 5pt),
  stroke: 0.4pt + suave,
  align: (left, left),
  table.header([*Escenario*], [*Carga*]),
  [`baseline.yaml` [E-92]],
  [Escalones de 60 s a 10, 25, 50, 75, 100, 150, 200 y 300 rps. Cada usuario
    virtual manda un request por una conexión nueva. Mezcla: 40 %
    `POST /exchange`, 30 % `GET /rates`, 20 % `GET /accounts` y 10 %
    `GET /log`.],

  [`sessions.yaml` [E-93]],
  [La misma mezcla, pero cada usuario virtual manda su request 4 veces por una
    conexión keep-alive. Suma escalones de 400, 600 y 800 rps.],
)

Cada exchange manda un `dni` aleatorio [E-92]. Los `403` y `502` que devuelve el
nodo trasladan la respuesta de ARCA (sección 6), así que no los contamos como
fallas del nodo.

== Primera ejecución: el límite fue el generador

Con `baseline.yaml`, el nodo respondió todos los escalones hasta 150 rps, con 3
timeouts en 24.600 requests [E-84]. En los escalones de 200 y 300 rps, 24.652 de los
30.000 requests terminaron en timeout [E-84].

El quiebre no estaba en Azure. El nodo abrió una conexión por cada request que
atendió y ninguna por los que terminaron en timeout [E-85]. El generador resuelve
el nombre del load balancer en cada conexión nueva, a 134 resoluciones por
segundo [E-86]. Con el nombre en `/etc/hosts`, una rampa contra `/` pasó los
200 rps con 3 timeouts en 10.000 requests [E-87].

A 300 rps, esa rampa tuvo 3.047 timeouts [E-87]. Entre los dos conteos, el nodo
abrió 35.991 conexiones para 35.953 respuestas [E-85] [E-110]: los SYNs de los
timeouts no llegaron al nodo. Por eso la segunda ejecución abre menos conexiones
y reusa cada una para 4 requests.

Los conteos por escalón toman los intervalos de 10 s que caen enteros dentro de
cada escalón de 60 s.

#[#set par(justify: false)
  #grid(
    columns: (1fr, 1fr),
    gutter: 6pt,
    prediccion(
      metrica: [P1: mediana de `GET /rates` en el cliente, 10 a 100 rps],
      predicho: [171 ms],
      observado: [169 ms en cada intervalo de 10 s],
      evidencia: "E-84",
    ),
    prediccion(
      metrica: [P2: mediana de la validación con ARCA, 10 a 100 rps],
      predicho: [370 ms],
      observado: [298 a 308 ms (mediana de cada escalón)],
      evidencia: "E-96",
    ),

    prediccion(
      metrica: [P3: mediana de `exchange.processing`, 10 rps],
      predicho: [355 ms],
      observado: [353,7 ms],
      evidencia: "E-97",
    ),
    prediccion(
      metrica: [P4: p95 de `POST /exchange` en el cliente, 10 rps],
      predicho: [1.040 ms],
      observado: [925 a 1.023 ms por intervalo de 10 s],
      evidencia: "E-84",
    ),

    prediccion(
      metrica: [P5 y P6: `502` y `403`, hasta 150 rps],
      predicho: [24 % y 25 % de los exchanges],
      observado: [25,1 % y 25,3 % (2.059 y 2.079 de 8.213)],
      evidencia: "E-84",
    ),
    prediccion(
      metrica: [P7: último escalón completo],
      predicho: [150 rps],
      observado: [150 rps, con el generador como límite],
      evidencia: "E-86",
    ),

    prediccion(
      metrica: [P8: CPU del nodo a 150 rps],
      predicho: [menos del 50 %],
      observado: [15,1 % de promedio, 18,2 % de máximo],
      evidencia: "E-98",
    ),
    prediccion(
      metrica: [P9: componente que limita],
      predicho: [Postgres, en la escritura del exchange],
      observado: [el generador; 0 esperas `Lock` en toda la ejecución],
      evidencia: "E-99",
    ),
  )]

Acertamos P1, P3, P5 y P6, que no dependen de la carga, y P4 quedó 17 ms por
encima del máximo observado. En el servidor, `GET /rates` tardó de 1,1 a 1,7 ms
de p50 [E-95]: P1 es casi toda latencia de red. ARCA respondió en unos 300 ms y no en los 371 ms
del issue \#14, medidos desde el jumpbox; no investigamos esa diferencia. P7
acertó el número por una causa que no predijimos, y P9 queda sin verificar:
Postgres no tuvo esperas `Lock` [E-99].

== Segunda ejecución: sesiones

La @tabla-sesiones resume cada escalón de `sessions.yaml`. Toma los cinco
intervalos de 10 s que caen enteros dentro de cada escalón de 60 s.

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
        [*CPU nodo (%)*],
        [*Lag máx. (ms)*],
      ),
      [10], [497], [496], [0], [172,5--175,9], [1,5], [576], [2,1], [1,8],
      [25], [1.248], [1.248], [0], [169--172,5], [1,2], [568], [3,2], [1,8],
      [50], [2.496], [2.493], [0], [169--172,5], [1,1], [509], [4,6], [3,0],
      [75], [3.758], [3.760], [0], [172,5], [1,0], [559], [6,2], [3,2],
      [100], [4.991], [4.991], [0], [172,5], [1,0], [568], [7,5], [3,6],
      [150], [7.508], [7.513], [0], [172,5], [1,0], [501], [10,3], [3,7],
      [200], [9.992], [9.993], [2], [172,5], [1,0], [542], [14,6], [4,5],
      [300], [15.016], [15.021], [1], [172,5], [1,0], [501], [21,7], [7,4],
      [400], [19.986], [19.993], [1], [172,5], [1,0], [517], [29,0], [16,4],
      [600], [29.951], [29.954], [4], [172,5], [1,2], [525], [36,9], [17,8],
      [800],
      [34.754],
      [32.981],
      [807],
      [172,5--982,6],
      [585,3],
      [2.553],
      [45,6],
      [13,8],
    )
  },
  caption: [Segunda ejecución por escalón. Cliente: rango de las medianas de
    cada intervalo de 10 s [E-94]. Servidor: máximo del p50 de Datadog por ruta
    [E-100]. CPU del nodo (user + system): promedio [E-103]. Lag: máximo del
    event loop [E-104].],
) <tabla-sesiones>

Hasta 600 rps, el nodo respondió cada escalón con 4 timeouts como máximo. La
mediana en el cliente quedó en 169 a 175,9 ms, la latencia de base más el
servicio [E-94]. En el servidor, el p50 de `GET /rates` no pasó de 1,5 ms y el
del exchange quedó entre 501 y 576 ms, sin tendencia con la carga [E-100].

=== Dónde se satura

El escalón de 800 rps se degradó en su segundo intervalo de 10 s. Las respuestas
bajaron de 7.961 a 4.592 por intervalo, menos que a 600 rps, y las sesiones
llegaron a 23 s [E-94]. El generador también mandó menos, de 7.993 a 5.610
requests, porque cada sesión espera su respuesta antes del siguiente request.

Datadog mide la latencia dentro del nodo, sin la red, y también muestra la
saturación. El p50 de `GET /rates` pasó de 1 a 585 ms, y el del exchange, de
unos 500 a 2.553 ms [E-100] [E-108]. La @tabla-componentes muestra los
componentes que no limitaron.

#figure(
  table(
    columns: (auto, 1fr),
    inset: (x: 6pt, y: 4pt),
    stroke: 0.4pt + suave,
    align: (left, left),
    table.header([*Componente*], [*A 800 rps*]),
    [CPU del nodo], [52 % de máximo [E-103]],
    [Event loop], [lag máximo de 13,8 ms [E-104]],
    [ARCA], [p50 de hasta 305,2 ms [E-101], 67 de sus 500 milicores [E-109]],

    [CPU de Postgres], [52,7 % de máximo en la ejecución [E-106]],
  ),
  caption: [Componentes con capacidad libre en el escalón de 800 rps.],
) <tabla-componentes>

Lo que crece es la espera fuera del event loop. `GET /rates` sólo hace una
consulta a Postgres, por un pool de `pg` sin `max`: 10 conexiones, el valor por
defecto [E-62]. Nuestra hipótesis es que los requests esperan una conexión libre
de ese pool.

Dos observaciones más la sostienen. `exchange.processing`, que excluye a ARCA, subió
su p50 a 3.941 ms [E-102]. Las esperas `Lock` de Postgres valen 0 en todas las
muestras hasta las 22:00 UTC, y 6 en la de las 22:01 [E-105]. Un exchange que
espera un lock retiene su conexión, y los demás requests esperan detrás.

No aislamos el pool con otra ejecución. El caso escalado suma un segundo pool de
10 conexiones contra el mismo Postgres, y pone a prueba la hipótesis.

Parte de los 1.279 timeouts de la ejecución son de la red [E-94]. El nodo abrió
39.431 conexiones para 40.650 sesiones [E-107]: al menos 1.219 sesiones nunca
llegaron al nodo. La saturación la prueba la latencia en el servidor, no los
timeouts.

#[#set par(justify: false)
  #grid(
    columns: (1fr, 1fr),
    gutter: 6pt,
    prediccion(
      metrica: [S1: mediana de `GET /rates` en el cliente, 10 a 300 rps],
      predicho: [171 ms],
      observado: [169 a 172,5 ms por intervalo de 10 s],
      evidencia: "E-94",
    ),
    prediccion(
      metrica: [S2: último escalón con el 99,5 % de respuestas],
      predicho: [600 rps],
      observado: [600 rps; a 800 rps, el 94,9 %],
      evidencia: "E-94",
    ),

    prediccion(
      metrica: [S3: CPU del nodo a 400 rps],
      predicho: [45 %],
      observado: [29,0 % de promedio],
      evidencia: "E-103",
    ),
    prediccion(
      metrica: [S4: componente que limita a 800 rps],
      predicho: [el proceso de Node: CPU de más del 85 % y lag de más de 50 ms],
      observado: [el pool de Postgres (hipótesis); CPU de 52 %, lag de 13,8 ms],
      evidencia: "E-100",
    ),

    prediccion(
      metrica: [S5: esperas `Lock` de Postgres, máximo por minuto],
      predicho: [0 o 1 en todos los escalones],
      observado: [0 hasta 600 rps; 6 al final de 800 rps],
      evidencia: "E-105",
    ),
    prediccion(
      metrica: [S6: CPU de Postgres a 600 rps],
      predicho: [65 %],
      observado: [40 % o menos],
      evidencia: "E-106",
    ),
  )]

Acertamos S1 y S2, pero S2 por otra causa: S4 esperaba que el nodo se quedara
sin CPU. Extrapolamos la CPU por request de la primera ejecución, y las sesiones
la bajan. A 150 rps, el nodo usó 15,1 % con una conexión por request [E-98] y
10,3 % con sesiones [E-103].

S6 escaló en proporción también la CPU que Postgres usa sin carga, un 5 % antes
de la ejecución [E-106]. S5 suponía locks de pocos milisegundos y no consideró
la cola del pool. Su razonamiento, además, atribuye al TP 1 una diferencia de
código que no existe (sección 12).
