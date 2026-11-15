#import "../plantilla.typ": *

= Caso escalado

Escalamos el VMSS a dos instancias `Standard_F1als_v7` cambiando
`vmss_instances` en Terraform [E-133] [E-134]. Postgres, ARCA, el escenario y
el generador de carga son los mismos que en el caso 1 nodo. La ejecución corrió
sobre el tag #commit("measured/scaled").

Las predicciones del caso, C1 a C9, están en `perf/predicciones.md` [E-132].
Las commiteamos en #sha("956edad"), antes de la ejecución, a partir de los
resultados del caso 1 nodo.

== Escenario

Repetimos la ejecución final del caso 1 nodo: el entorno `pool-ramp`, con
escalones de 10 a 1.000 rps y la misma mezcla [E-92]. El generador es el mismo
equipo, por ethernet cableada [E-89], con una latencia de base de 169 ms de
mediana [E-90].

La hipótesis fue que el throughput no se duplica. Con 1 nodo, el límite fue la
escritura de los exchanges sobre las cuentas internas en Postgres, y un segundo
nodo no la acelera. Predijimos el mismo escalón completo que con 1 nodo,
600 rps, y menos de 750 respuestas por segundo.

== Resultados

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
        [*CPU nodos (%)*],
      ),
      [10], [500], [497], [0], [172,5], [1,4], [498], [9,9], [1,4 / 1,2],
      [25], [1.250], [1.247], [0], [172,5], [1,3], [446], [24,9], [1,8 / 2,3],
      [50], [2.500], [2.499], [0], [172,5], [1,2], [517], [50,1], [2,9 / 3,2],
      [75], [3.750], [3.743], [0], [175,9], [1,1], [483], [74,9], [3,6 / 4,5],
      [100], [5.000], [5.005], [0], [172,5], [1,1], [490], [100,0], [5,3 / 5,4],
      [150], [7.500], [7.496], [0], [175,9], [1,2], [494], [149,9], [7,0 / 8,2],
      [200],
      [10.000],
      [10.004],
      [0],
      [172,5],
      [1,1],
      [486],
      [199,9],
      [8,3 / 9,8],

      [300],
      [15.000],
      [14.990],
      [0],
      [179,5],
      [1,8],
      [501],
      [300,3],
      [9,2 / 11,3],

      [400],
      [20.000],
      [20.010],
      [0],
      [172,5--175,9],
      [1,1],
      [505],
      [400,3],
      [11,3 / 15,6],

      [600],
      [30.000],
      [28.717],
      [63],
      [183,1--1.107,9],
      [327,3],
      [2.142],
      [568,5],
      [15,7 / 20,7],

      [800],
      [40.002],
      [26.647],
      [12.318],
      [982,6--1.153,1],
      [744,4],
      [2.890],
      [534,0],
      [18,0 / 19,5],

      [1.000],
      [50.002],
      [24.745],
      [23.788],
      [982,6--1.465,9],
      [810,7],
      [3.123],
      [479,0],
      [17,3 / 19,8],
    )
  },
  caption: [Ejecución escalada por escalón, con el método de la @tabla-pool.
    Cliente: rango de las medianas de cada intervalo de 10 s [E-135].
    Servidor: mediana del p50 de Datadog por ruta [E-136]. Atendidos: respuestas
    de los dos nodos por segundo, sin los 10 s de cada borde [E-137]. CPU de
    cada nodo, user + system: promedio de los 40 s centrales del escalón
    [E-139].],
) <tabla-escalado>

Hasta 400 rps, los dos nodos respondieron cada escalón completo, con la misma
latencia que el caso 1 nodo [E-135] [E-114]. El escalón de 600 rps no se
completó: a los 20 s, la mediana en el cliente subió de 179,5 a 497,8 ms, y hubo
63 timeouts [E-135].

El throughput bajó al escalar. Los dos nodos atendieron 568,5 respuestas por
segundo como máximo, contra 647,6 de 1 nodo [E-137] [E-116]. A 800 y 1.000 rps
atendieron 534,0 y 479,0.

La demora está en el servicio. A 600 rps, el p50 de `GET /rates` en el servidor
fue de 327,3 ms, contra 2,8 ms con 1 nodo [E-136] [E-115]. `GET /rates` en el
cliente menos su p50 en el servidor quedó entre 152 y 171 ms, la latencia de
base [E-135] [E-136]. El generador usó toda su CPU desde 600 rps, como en el
caso 1 nodo, sin agregar demora [E-149] [E-127].

La @tabla-componentes-escalado muestra los componentes que no limitaron.

#figure(
  table(
    columns: (auto, 1fr),
    inset: (x: 6pt, y: 4pt),
    stroke: 0.4pt + suave,
    align: (left, left),
    table.header([*Componente*], [*En toda la ejecución*]),
    [CPU de los nodos], [22,9 % de máximo [E-139]],
    [Event loop], [lag máximo de 27,7 ms [E-140]],
    [ARCA], [p50 de 253 a 351 ms [E-141], 66 de sus 500 milicores [E-147]],
    [Procesos de Node], [sin reinicios ni descartes de conexiones [E-148]],
    [Load balancer],
    [50,5 % de las respuestas a un nodo, 49,5 % al otro [E-138]],
  ),
  caption: [Componentes con capacidad libre en la ejecución escalada.],
) <tabla-componentes-escalado>

El límite sigue en Postgres, y llegó antes. Con la misma carga, Postgres usó más
CPU que con 1 nodo. En el minuto del escalón de 600 rps promedió 63,0 %, contra
50,5 % [E-142] [E-121]. Desde 800 rps quedó en 92 %, contra 68,2 % a 79,8 %.

Las conexiones activas en Postgres llegaron a 28, contra 19 con 1 nodo
[E-144] [E-145]. Cada nodo abre su propio pool de 10 [E-62], así que hasta 20
transacciones compiten por las filas de las cuentas internas. Las esperas
`Lock` llegaron a 12, contra 8 [E-143] [E-122].

Interpretamos que más transacciones simultáneas sobre las mismas filas le cuestan
a Postgres más CPU por request. Con un solo vCore, Postgres se satura antes y
atiende menos. No medimos ese costo por transacción. Postgres tampoco se quedó
sin créditos de CPU: bajaron de 37 a 35 [E-146].

El dashboard muestra huecos en las series del cliente desde 800 rps [E-150]. Por
eso medimos con el reporte crudo de Artillery y con las respuestas de los nodos.

== Predicciones

#[#set par(justify: false)
  #grid(
    columns: (1fr, 1fr),
    gutter: 6pt,
    prediccion(
      metrica: [C1: ¿el throughput escala en proporción a los nodos?],
      predicho: [no],
      observado: [no: bajó de 647,6 a 568,5 respuestas por segundo],
      evidencia: "E-137",
    ),
    prediccion(
      metrica: [C2: último escalón completo],
      predicho: [600 rps],
      observado: [400 rps],
      evidencia: "E-135",
    ),

    prediccion(
      metrica: [C3: máximo de respuestas por segundo],
      predicho: [menos de 750],
      observado: [568,5],
      evidencia: "E-137",
    ),
    prediccion(
      metrica: [C4: componente que limita],
      predicho: [Postgres, en la escritura sobre las cuentas internas],
      observado: [Postgres, por CPU, con más esperas `Lock`],
      evidencia: "E-142",
    ),

    prediccion(
      metrica: [C5: máximo de esperas `Lock`],
      predicho: [más de 8],
      observado: [12],
      evidencia: "E-143",
    ),
    prediccion(
      metrica: [C6: CPU de Postgres a 600 rps],
      predicho: [50 %, como con 1 nodo],
      observado: [63,0 % de promedio en el minuto],
      evidencia: "E-142",
    ),

    prediccion(
      metrica: [C7: CPU de cada nodo a 600 rps],
      predicho: [18 %],
      observado: [15,7 % y 20,7 %],
      evidencia: "E-139",
    ),
    prediccion(
      metrica: [C8: parte de las respuestas por nodo],
      predicho: [50 %, con un margen de 5 puntos],
      observado: [50,5 % y 49,5 %],
      evidencia: "E-138",
    ),

    prediccion(
      metrica: [C9: mediana en el cliente, 10 a 600 rps],
      predicho: [172,5 a 183,1 ms],
      observado: [172,5 a 179,5 ms hasta 400 rps; hasta 1.107,9 ms a 600 rps],
      evidencia: "E-135",
    ),
  )]

Acertamos que el throughput no escala (C1), el componente (C4) y el reparto del
load balancer (C8). También acertamos C5 y C7: más esperas `Lock` y la mitad de
CPU por nodo.

Erramos el escalón (C2), la CPU de Postgres (C6) y la latencia a 600 rps (C9).
Las tres fallan por el mismo supuesto. C6 suponía que, a igual carga, Postgres
hace el mismo trabajo venga de uno o de dos nodos. La ejecución lo refuta: con
20 conexiones, Postgres usó más CPU por request y se saturó antes.

C3 se cumplió por un margen que no esperábamos. Predijimos un techo apenas más
alto que con 1 nodo, y fue más bajo. La predicción también nombraba una
alternativa: que el límite de 1 nodo fuera el pool de 10 conexiones y no las
filas. Duplicar las conexiones empeoró el throughput, así que la descartamos.

== Cuello de botella

El cuello de botella es la CPU de Postgres, y crece con la cantidad de
transacciones simultáneas sobre las cuentas internas. Agregar nodos agrega
conexiones, y con ellas más contención.
