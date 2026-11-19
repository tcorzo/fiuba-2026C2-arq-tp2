#import "../../plantilla.typ": *

#tactica(
  nombre: "Tope de conexiones a Postgres",
  qa: ("Performance", "Escalabilidad"),
  base: "measured/db-pool-cap-base",
  commit: "measured/db-pool-cap",
  problema: [
    La base es la ejecución de la táctica TLS (sección 9.1): 2 nodos, cada uno
    con un pool de 10 conexiones a Postgres [E-301] [E-302]. Desde la estación
    cableada, la latencia de base por HTTPS es de 169 ms de mediana [E-303].

    Con 2 nodos, el servicio atendió menos que con 1. En el escalón de 800 rps,
    la base respondió 573,2 requests por segundo, y el caso de 1 nodo, 647,6
    [E-305] [E-116]. Postgres siguió como límite, pero cada respuesta le costó
    más CPU: 1,13 ms a 630 respuestas por segundo, contra 1,02 ms a 668 con 1
    nodo [E-305] [E-307] [E-116] [E-121].

    También creció la contención. El máximo por minuto de sesiones de Postgres
    esperando un lock pasó de 8 con 1 nodo a 16 en la base [E-122] [E-308].
    Las conexiones activas subieron de 19 a 29: las 10 del pool del segundo
    nodo [E-148] [E-309].

    Cada exchange aprobado actualiza las mismas dos filas de `accounts`: la
    cuenta de ARS y la de USD. Con 1 nodo, compiten por ellas hasta 10
    transacciones; con dos pools de 10, hasta 20. Nuestra hipótesis es que esa
    competencia explica el costo extra por respuesta. La táctica la pone a
    prueba: achica el pool de cada nodo para que Postgres vuelva a recibir 10
    transacciones.

    Antes de medir la base, predijimos B1 a B9 [E-300], y acertamos siete. B6
    esperaba el de 400 rps como último escalón completo, como en el caso
    escalado, y la base completó el de 600 [E-304] [E-138]. No medimos la
    causa. B1 esperaba 65 % de CPU de Postgres a 600 rps, y observamos 71,3 %
    [E-307]. Esa diferencia viene de un problema de método que explicamos en
    los resultados.
  ],
  prediccion: [
    Con 5 conexiones por nodo, Postgres vuelve a recibir como mucho 10
    transacciones a la vez, igual que con 1 nodo. Esperábamos que trabajara
    como con 1 nodo: menos CPU por respuesta, no más de 8 sesiones esperando un
    lock y entre 640 y 700 respuestas por segundo a 800 rps. Commiteamos las
    predicciones, D1 a D11, en #sha("c7b3646"), después de medir la base y
    antes de medir la táctica [E-320].
  ],
  implementacion: [
    El tamaño del pool pasó a ser la variable `db_pool_max` del stack
    `platform`. Terraform la publica en `app_config`, y `connectStore` se la
    pasa a `pg.Pool` como `max` [E-322]. Primero la agregamos en 10, el valor
    por defecto de pg, en un commit que no cambia el comportamiento
    (#sha("472e6aa")). La táctica es un cambio de una línea, de 10 a 5 [E-301]
    [E-321]. Aplicamos `platform` y desplegamos de nuevo la app con Ansible,
    sobre las mismas dos instancias [E-323].

    Con el tope, las conexiones activas en Postgres bajaron de 29 a 20 [E-309]
    [E-329]: 9 menos, frente a las 10 que sacamos de los pools.
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
          [573,2 [E-305]],
          [681,8 [E-325]],

          [Timeouts del escalón de 800 rps], [8.253 [E-304]], [3.901 [E-324]],
          [Último escalón completo], [600 rps], [600 rps],
          [Mediana en el cliente, escalón de 600 rps],
          [262,5 a 478,3 ms [E-304]],
          [183,1 a 257,3 ms [E-324]],

          [p50 de `GET /rates` en el servidor, 600 rps],
          [131,1 ms [E-306]],
          [5,2 ms [E-326]],

          [p50 de `POST /exchange` en el servidor, 600 rps],
          [1.082,5 ms [E-306]],
          [589,9 ms [E-326]],

          [Máximo de sesiones esperando un lock], [16 [E-308]], [6 [E-328]],
          [CPU de Postgres por transacción confirmada],
          [0,513 ms [E-310]],
          [0,465 ms [E-330]],

          [CPU máxima de los nodos], [38,3 % [E-311]], [35,8 % [E-331]],
        )
      },
      caption: [Base y táctica, desde la misma estación y con el mismo
        escenario, con el método de la @tabla-escalado. Respuestas por
        segundo: promedio de Datadog en los 40 s centrales del escalón. Mediana
        en el cliente: rango de las medianas de los intervalos de 10 s enteros
        del escalón. CPU por transacción: segundos de vCPU de Azure
        Monitor durante la ejecución, divididos por el aumento de
        `xact_commit`.],
    ) <tabla-tope>

    El tope subió un 19 % las respuestas del escalón de 800 rps y redujo los
    timeouts a menos de la mitad. La mejora más grande está en las lecturas: a
    600 rps, el p50 de `GET /rates` en el servidor bajó de 131,1 a 5,2 ms.
    Hasta 400 rps no hay diferencia: las dos ejecuciones quedan dentro de la
    variación de la latencia de base [E-304] [E-324] [E-303].

    Postgres tuvo créditos de CPU de sobra en las dos ejecuciones: bajaron de
    194 a 192 [E-313] [E-333]. Los dashboards de Datadog están en [E-314] y
    [E-334].

    *El método por escalón comparó cargas distintas.* Azure Monitor da la CPU
    de Postgres por minuto, y los escalones de 60 s no coinciden con esos
    minutos. El método toma, para cada escalón, el minuto más cargado de los
    que se superponen con él. En la base, ese minuto tuvo 20 s de 600 rps y
    40 s de 800; en la táctica, 40 s y 20 s. Por eso B1, D5 y D6 compararon
    cargas distintas. La @tabla-tope-minutos compara minutos con carga
    parecida, sin esa regla:

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
        Azure Monitor dividido por las respuestas de Datadog en ese minuto
        [E-305] [E-307] [E-325] [E-327].],
    ) <tabla-tope-minutos>

    Por debajo de 500 respuestas por segundo, las dos ejecuciones le cuestan
    casi lo mismo a Postgres: 0,95 y 1,01 ms por respuesta. Cerca de 635, la
    táctica gasta 0,91 ms y la base 1,13 ms: un 20 % menos, y menos que los
    1,02 ms de 1 nodo [E-121]. La base llegó a 91,8 % de CPU con 553 respuestas
    por segundo; la táctica atendió 686,8 con 80,2 %.

    #[#set par(justify: false)
      #grid(
        columns: (1fr, 1fr),
        gutter: 6pt,
        prediccion(
          metrica: [D1: ¿mejora el throughput sostenido?],
          predicho: [sí],
          observado: [sí: de 573,2 a 681,8 respuestas por segundo a 800 rps],
          evidencia: "E-325",
        ),
        prediccion(
          metrica: [D2: respuestas por segundo a 800 rps],
          predicho: [entre 640 y 700],
          observado: [681,8],
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
          observado: [5,2 ms],
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

    Acertamos D1 a D3 y D7 a D9: con menos transacciones compitiendo por las
    mismas filas, subió el throughput. D5 y D6 fallaron por la regla de
    método. Con la comparación por minuto, la táctica gasta 0,91 ms por
    respuesta, dentro del margen de D6. D10 quedó afuera por 0,005 ms.

    D4 y D11 quedaron limitadas por el generador. En las dos ejecuciones, su
    CPU idle bajó a 1 % desde la mitad del escalón de 600 rps [E-312] [E-332].
    Desde ahí, la latencia en el cliente incluye la espera en el propio
    generador, y no podemos atribuir el límite de 800 rps sólo a Postgres.

    También cambió cómo Postgres lee `accounts`. Los recorridos secuenciales
    bajaron de 209.455 a 78.698, y los de índice subieron de 165.939 a 315.148
    [E-310] [E-330]. Con 4 filas en la tabla, suponemos que el efecto es menor,
    pero no lo medimos.
  ],
  compromiso: [
    El tope traslada la espera de Postgres a Node. `connectStore` no configura
    `connectionTimeoutMillis` [E-322], que en pg vale 0 por defecto: un request
    espera una conexión libre sin límite de tiempo. Si llega más carga de la
    que Postgres atiende, la cola crece dentro de cada proceso.

    El tope correcto depende de la cantidad de nodos. Con 5 por nodo, 2 nodos
    suman las 10 conexiones de 1 nodo, pero 3 sumarían 15. Si un nodo cae, el
    otro atiende toda la carga con 5 conexiones. Cada cambio de
    `vmss_instances` obliga a recalcular `db_pool_max` en el mismo commit.

    Por debajo de la saturación, el tope no aporta nada: hasta 400 rps, las dos
    ejecuciones responden con la misma latencia [E-304] [E-324].
  ],
)
