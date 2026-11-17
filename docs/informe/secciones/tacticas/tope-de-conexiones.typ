#import "../../plantilla.typ": *

#tactica(
  nombre: "Tope de conexiones a Postgres",
  qa: ("Performance", "Escalabilidad"),
  base: "measured/db-pool-cap-base",
  commit: "measured/db-pool-cap",
  problema: [
    La base es la ejecución de la táctica TLS (sección 9.1), desde la estación
    cableada: 2 nodos con 10 conexiones a Postgres cada uno [E-301] [E-302].
    Su latencia de base por HTTPS es de 169 ms de mediana [E-303].

    Con 2 nodos, Postgres sigue siendo el límite y gasta más CPU por respuesta
    que con 1. A 630 respuestas por segundo, cada respuesta le costó 1,13 ms de
    CPU, contra 1,02 ms de 1 nodo a 668 [E-305] [E-307] [E-116] [E-121]. Las
    sesiones que esperan un lock llegaron a 16, contra 8, y las conexiones
    activas a 29, contra 19 [E-308] [E-309] [E-122] [E-148]. En el escalón de
    800 rps, la base atendió 584,9 respuestas por segundo, y 1 nodo 673,9
    [E-305] [E-116].

    Cada exchange aprobado actualiza las mismas dos filas de `accounts`, ARS y
    USD. Con dos pools de 10, hasta 20 transacciones compiten por ellas.
    Interpretamos que esa competencia es el costo extra, y la táctica lo pone a
    prueba: limita las conexiones de cada nodo.

    Las predicciones de la base, B1 a B9, están en `perf/predicciones.md`
    [E-300]. Acertamos siete. B6 predijo 400 rps como último escalón completo, y
    la base completó el de 600 rps, que el caso escalado sin TLS no completó
    [E-304] [E-138]. No medimos la causa. B1 predijo 65 % de CPU a 600 rps, y
    observamos 71,3 % [E-307], con el problema de método que explicamos en los
    resultados.
  ],
  prediccion: [
    Con 5 conexiones por nodo, Postgres recibe las mismas 10 transacciones
    simultáneas que con 1 nodo. Predijimos que trabaja como con 1 nodo: menos
    CPU por respuesta, a lo sumo 8 esperas `Lock` y entre 640 y 700 respuestas
    por segundo en el escalón de 800 rps. Las predicciones, D1 a D11, están en
    `perf/predicciones.md` [E-320]. Las commiteamos en #sha("c7b3646"), después
    de la base y antes de la ejecución de la táctica.
  ],
  implementacion: [
    `db_pool_max` es una variable del stack `platform`. Llega a la app por
    `app_config`, y `connectStore` la pasa a `pg.Pool` como `max` [E-322]. La
    agregamos con 10, el valor por defecto de pg, en un commit sin cambio de
    comportamiento (#sha("472e6aa")). La táctica cambia una línea: 10 pasa a 5
    [E-301] [E-321]. Aplicamos `platform` y redesplegamos la app con Ansible,
    sobre las mismas dos instancias [E-323].

    Las conexiones activas en Postgres bajaron de 29 a 20 [E-309] [E-329]: 9
    menos, casi las 10 que quitamos de los pools.
  ],
  resultados: [
    #figure(
      {
        set text(size: 8pt)
        table(
          columns: 3,
          inset: (x: 4pt, y: 3pt),
          stroke: 0.4pt + suave,
          align: (left, right, right),
          table.header([], [*Base (10 por nodo)*], [*Táctica (5 por nodo)*]),
          [Respuestas por segundo, escalón de 800 rps],
          [584,9 [E-305]],
          [690,5 [E-325]],

          [Timeouts del escalón de 800 rps], [8.253 [E-304]], [3.901 [E-324]],
          [Último escalón completo], [600 rps], [600 rps],
          [Mediana en el cliente, escalón de 600 rps],
          [179,5 a 478,3 ms [E-304]],
          [183,1 a 257,3 ms [E-324]],

          [p50 de `GET /rates` en el servidor, 600 rps],
          [131,1 ms [E-306]],
          [3,9 ms [E-326]],

          [p50 de `POST /exchange` en el servidor, 600 rps],
          [1.082,5 ms [E-306]],
          [572,0 ms [E-326]],

          [Máximo de sesiones esperando un lock], [16 [E-308]], [6 [E-328]],
          [CPU de Postgres por transacción confirmada],
          [0,513 ms [E-310]],
          [0,465 ms [E-330]],

          [CPU máxima de los nodos], [38,3 % [E-311]], [35,8 % [E-331]],
        )
      },
      caption: [Base y táctica, misma estación y mismo escenario. Respuestas
        por segundo: Datadog, promedio de los 40 s centrales del escalón.
        Mediana en el cliente: rango de las medianas de cada intervalo de
        10 s. CPU por transacción: segundos de vCPU de Azure Monitor durante
        la ejecución, sobre el aumento de `xact_commit`.],
    ) <tabla-tope>

    El tope atendió un 18 % más en el escalón de 800 rps, con menos de la
    mitad de timeouts. Las lecturas dejaron de esperar a Postgres: a 600 rps,
    `GET /rates` bajó de 131,1 a 3,9 ms en el servidor. Hasta 400 rps, las dos
    ejecuciones responden igual, dentro del ruido de la latencia de base
    [E-304] [E-324] [E-303]. Postgres no se quedó sin créditos de CPU: bajaron de 194 a 192 en las
    dos ejecuciones [E-313] [E-333]. Los dashboards de Datadog de las dos
    están en [E-314] y [E-334].

    *El método por escalón comparó cargas distintas.* Para la CPU de Postgres
    de un escalón, el método toma el minuto más cargado de los que se
    superponen con él. En la base, ese minuto tuvo 20 s del escalón de 600 rps
    y 40 s del de 800. En la táctica, 40 s y 20 s. Por eso B1, D5 y D6 miden
    cargas distintas. La comparación por minuto, a carga parecida, no depende
    de esa regla:

    #figure(
      {
        set text(size: 8pt)
        table(
          columns: 4,
          inset: (x: 4pt, y: 3pt),
          stroke: 0.4pt + suave,
          align: (left, right, right, right),
          table.header(
            [*Minuto (UTC)*],
            [*Respuestas por segundo*],
            [*CPU de Postgres*],
            [*CPU por respuesta*],
          ),
          [Base, 18:06], [504,0], [47,6 %], [0,95 ms],
          [Base, 18:07], [630,3], [71,3 %], [1,13 ms],
          [Base, 18:08], [553,1], [91,8 %], [1,66 ms],
          [Táctica, 18:33], [463,5], [47,0 %], [1,01 ms],
          [Táctica, 18:34], [641,3], [58,2 %], [0,91 ms],
          [Táctica, 18:35], [686,8], [80,2 %], [1,17 ms],
        )
      },
      caption: [CPU de Postgres por respuesta, minuto a minuto: promedio de
        Azure Monitor sobre las respuestas de Datadog en ese minuto [E-305]
        [E-307] [E-325] [E-327].],
    ) <tabla-tope-minutos>

    Por debajo de 500 respuestas por segundo, las dos cuestan lo mismo. A unas
    635, la táctica gasta 0,91 ms por respuesta y la base 1,13 ms: un 20 %
    menos, al nivel de 1 nodo. La base se saturó a 553 respuestas por segundo,
    con 91,8 % de CPU. La táctica atendió 686,8 con 80,2 %.

    #[#set par(justify: false)
      #grid(
        columns: (1fr, 1fr),
        gutter: 6pt,
        prediccion(
          metrica: [D1: ¿mejora el throughput sostenido?],
          predicho: [sí],
          observado: [sí: de 584,9 a 690,5 respuestas por segundo a 800 rps],
          evidencia: "E-325",
        ),
        prediccion(
          metrica: [D2: respuestas por segundo a 800 rps],
          predicho: [entre 640 y 700],
          observado: [690,5],
          evidencia: "E-325",
        ),

        prediccion(
          metrica: [D3: último escalón completo],
          predicho: [600 rps; 800 rps no],
          observado: [600 rps; 3.901 timeouts a 800 rps],
          evidencia: "E-324",
        ),
        prediccion(
          metrica: [D4: mediana a 600 rps sobre la latencia de base],
          predicho: [menos de 20 ms],
          observado: [14,1 a 88,3 ms],
          evidencia: "E-324",
        ),

        prediccion(
          metrica: [D5: CPU de Postgres a 600 rps],
          predicho: [50 %, con un margen de 5 puntos],
          observado: [58,2 %],
          evidencia: "E-327",
        ),
        prediccion(
          metrica: [D6: CPU de Postgres por respuesta a 600 rps],
          predicho: [0,84 ms, con un margen de 0,1 ms],
          observado: [0,97 ms],
          evidencia: "E-327",
        ),

        prediccion(
          metrica: [D7: máximo de esperas `Lock`],
          predicho: [8 o menos],
          observado: [6],
          evidencia: "E-328",
        ),
        prediccion(
          metrica: [D8: máximo de conexiones activas],
          predicho: [19, con un margen de 1],
          observado: [20],
          evidencia: "E-329",
        ),

        prediccion(
          metrica: [D9: p50 de `GET /rates` a 600 rps],
          predicho: [menos de 10 ms],
          observado: [3,9 ms],
          evidencia: "E-326",
        ),
        prediccion(
          metrica: [D10: CPU de Postgres por transacción],
          predicho: [0,46 ms o menos],
          observado: [0,465 ms, un 9,4 % menos que la base],
          evidencia: "E-330",
        ),

        prediccion(
          metrica: [D11: componente que limita],
          predicho: [Postgres, por CPU, desde 800 rps],
          observado: [Postgres con 80 a 88 % de CPU, y el generador saturado],
          evidencia: "E-332",
        ),
      )]

    Acertamos D1 a D3 y D7 a D9: el tope bajó la competencia por las filas y
    subió el throughput. D5 y D6 fallan por el método de arriba. Con la
    comparación por minuto, el costo por respuesta queda en 0,91 ms, dentro
    del margen de D6. D10 erró por 0,005 ms.

    D4 y D11 tienen el mismo límite: el generador. Su CPU idle bajó a 1 %
    desde la mitad del escalón de 600 rps, en las dos ejecuciones [E-312]
    [E-332]. Desde ahí, la latencia en el cliente incluye la espera en el
    generador, y no podemos atribuir el límite de 800 rps solo a Postgres.

    Otro cambio entre ejecuciones: Postgres resolvió las lecturas de `accounts`
    con otro plan. Los recorridos secuenciales bajaron de 209.455 a 78.698, y
    los de índice subieron de 165.939 a 315.148 [E-310] [E-330]. La tabla tiene
    4 filas, así que tomamos el efecto como menor, pero no lo medimos.
  ],
  compromiso: [
    La espera pasa de Postgres a Node. `connectStore` no configura
    `connectionTimeoutMillis` [E-322], y su valor por defecto en pg es 0: un
    request espera una conexión libre sin límite de tiempo. Con más carga de
    la que Postgres atiende, la cola crece dentro de cada proceso.

    El tope depende de la cantidad de nodos. Con 5 conexiones por nodo, 2
    nodos dan las 10 de 1 nodo. Con 3 nodos vuelven a ser 15, y si un nodo cae,
    el que queda atiende todo con 5. Cada cambio de `vmss_instances` exige
    recalcular `db_pool_max` en el mismo commit.

    Por debajo de la saturación, el tope no cambia nada: hasta 400 rps, base y
    táctica responden con la misma latencia [E-304] [E-324].
  ],
)
