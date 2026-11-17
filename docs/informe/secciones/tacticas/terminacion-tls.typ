#import "../../plantilla.typ": *

#tactica(
  nombre: "Terminación TLS",
  qa: ("Seguridad",),
  base: "measured/scaled",
  commit: "measured/db-pool-cap-base",
  problema: [
    En el caso escalado, ningún componente cifra el tráfico. El cliente llega
    al load balancer en HTTP al puerto 80, y el load balancer reenvía TCP al
    3000 [E-217] [E-19]. Cada `POST /exchange` lleva el `dni` del cliente en el
    body [E-77], en claro por internet. En el TP 1, nginx terminaba TLS (H-38)
    [E-38]. Acá no hay nginx, y el load balancer sólo reenvía TCP [E-217].
  ],
  prediccion: [
    Predijimos que TLS no cambia la latencia que mide Artillery ni el
    componente que limita, y que su costo aparece en la CPU de los nodos. El
    handshake pasa una vez por conexión, y `pool-ramp` reutiliza las
    conexiones. Las predicciones, T1 a T6, están en `perf/predicciones.md`
    [E-154]. Las commiteamos en #sha("19e050d"), antes de la ejecución.

    Las escribimos para una ejecución desde una laptop por WiFi. Esa ejecución
    no es comparable con el caso escalado, porque cambia el generador, y no la
    usamos. Evaluamos T1 a T6 con la ejecución desde la estación cableada, que
    es también la base del tope de conexiones. T1 compara cada mediana contra
    la latencia de base de su generador, así que aplica igual.
  ],
  implementacion: [
    El proceso de Node termina TLS con `node:https`, sin componentes nuevos
    (#codigo("node/server.js", "18-31", en: "3ee54a4")). Atiende HTTPS en el
    3443, con TLS 1.2 como mínimo y `Strict-Transport-Security` en cada
    respuesta. En el 3080 atiende HTTP y sólo responde `308` hacia HTTPS
    (#codigo("node/transport.js", "19-30", en: "3ee54a4")). El `308`, a
    diferencia de un `301`, conserva el método y el body del `POST /exchange`.

    pm2 corre el proceso como `azureuser`, que no puede abrir puertos menores
    que 1024. Por eso el load balancer traduce 443 → 3443 y 80 → 3080, y el
    probe mira el 3443 [E-155] [E-156]. El NSG de los nodos permite 3443 y
    3080, y ya no el 3000 (#codigo("infra/modules/network/main.tf", "74-91", en: "3ee54a4")).

    El certificado es autofirmado, ECDSA P-256, para el FQDN del load
    balancer. Lo genera `mise run app:certs` en `certs/`, que git ignora
    (#codigo("mise.toml", "280-301", en: "3ee54a4")). Ansible copia el par a
    cada nodo, con la clave privada en modo `0600`
    (#codigo("ansible/vmss_deploy.yml", "16-33", en: "3ee54a4")). Artillery
    apunta a `https://` y no valida el certificado, como en el TP 1.

    Con la táctica desplegada, `curl` negocia TLS 1.3 con ese certificado y
    recibe `200` con HSTS [E-157]. `openssl s_client` verifica el nombre del
    servidor [E-159]. Un `POST /exchange` al puerto 80 recibe `308` hacia
    `https://` [E-158].
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
          table.header([], [*Escalado (HTTP)*], [*TLS*]),
          [Mediana en el cliente, de 10 a 400 rps],
          [172,5 a 179,5 ms [E-138]],
          [175,9 a 186,8 ms [E-304]],

          [p95 en el cliente, de 10 a 400 rps],
          [889 a 983 ms [E-138]],
          [872 a 1.086 ms [E-304]],

          [Último escalón completo], [400 rps [E-138]], [600 rps [E-304]],
          [Respuestas por segundo, escalón de 800 rps],
          [534,0 [E-140]],
          [573,2 [E-305]],

          [CPU de cada nodo, escalón de 400 rps],
          [11,3 y 15,6 % [E-142]],
          [23,5 y 13,1 % [E-311]],

          [CPU máxima de los nodos], [22,9 % [E-142]], [38,3 % [E-311]],
          [Lag máximo del event loop, 400 rps],
          [4,5 y 5,3 ms [E-143]],
          [14,8 y 2,5 ms [E-161]],

          [Conexiones aceptadas por los dos nodos],
          [11.524 [E-163]],
          [7.542 [E-162]],
        )
      },
      caption: [Caso escalado y TLS, desde la estación cableada, con
        `pool-ramp`. Mediana y p95: rango de los intervalos de 10 s enteros
        de cada escalón. Respuestas por segundo y CPU: Datadog, promedio de
        los 40 s centrales del escalón. La latencia de base es de 169 ms con
        HTTP y con HTTPS [E-90] [E-303].],
    ) <tabla-tls>

    Hasta 400 rps, TLS no cambió la latencia. En cada escalón, la mediana
    quedó a lo sumo 10,9 ms sobre la del caso escalado, dentro del rango de
    15 ms de la latencia de base [E-303]. El costo apareció en la CPU de los
    nodos, pero repartido de forma desigual:

    #figure(
      {
        set text(size: 8pt)
        table(
          columns: 5,
          inset: (x: 4pt, y: 3pt),
          stroke: 0.4pt + suave,
          align: (left, right, right, right, right),
          table.header(
            [*Nodo*],
            [*400 rps: rps / CPU*],
            [*600 rps: rps / CPU*],
            [*CPU cada 100 rps, 600 rps*],
            [*Lag máximo, 400 rps*],
          ),
          [Escalado, nodo 0], [189 / 11,3 %], [273 / 15,7 %], [5,8 %], [4,5 ms],
          [Escalado, nodo 1], [211 / 15,6 %], [295 / 20,7 %], [7,0 %], [5,3 ms],
          [TLS, nodo 0], [175 / 23,5 %], [300 / 31,2 %], [10,4 %], [14,8 ms],
          [TLS, nodo 2], [225 / 13,1 %], [302 / 17,2 %], [5,7 %], [2,5 ms],
        )
      },
      caption: [Requests por segundo que atendió cada nodo y su CPU, promedio
        de los 40 s centrales del escalón [E-141] [E-142] [E-143] [E-160]
        [E-311] [E-161].],
    ) <tabla-tls-nodos>

    El nodo 2 gastó por request lo mismo que los nodos sin TLS. El nodo 0
    gastó casi el doble: a 600 rps atendió los mismos requests que el nodo 2,
    con 31,2 % de CPU contra 17,2 %. Los handshakes no explican la
    diferencia. Los dos nodos aceptaron casi las mismas conexiones, 3.706 y
    3.836 [E-162], y entre los dos, menos que sin TLS [E-163]. No medimos la
    causa: la evidencia tiene la CPU total de cada nodo, no la de cada
    proceso. Con esta ejecución no podemos separar el costo de TLS de la
    diferencia entre los nodos.

    #[#set par(justify: false)
      #grid(
        columns: (1fr, 1fr),
        gutter: 6pt,
        prediccion(
          metrica: [T1: mediana de 10 a 400 rps, sobre la del caso escalado],
          predicho: [menos de 19 ms de diferencia],
          observado: [hasta 10,9 ms],
          evidencia: "E-304",
        ),
        prediccion(
          metrica: [T2: último escalón completo],
          predicho: [400 rps],
          observado: [600 rps, sin timeouts],
          evidencia: "E-304",
        ),

        prediccion(
          metrica: [T3: componente que limita],
          predicho: [Postgres],
          observado: [Postgres, hasta 91,8 % de CPU y 16 esperas `Lock`],
          evidencia: "E-307",
        ),
        prediccion(
          metrica: [T4: CPU de cada nodo a 400 rps],
          predicho: [unos 13,5 y 20 %],
          observado: [13,1 y 23,5 %],
          evidencia: "E-311",
        ),

        prediccion(
          metrica: [T5: CPU máxima de los nodos],
          predicho: [entre 22,9 y 30 %],
          observado: [38,3 %],
          evidencia: "E-311",
        ),
        prediccion(
          metrica: [T6: diferencia de CPU entre nodos a 400 rps],
          predicho: [de 6 a 8 puntos],
          observado: [10,3 puntos],
          evidencia: "E-311",
        ),
      )]

    Acertamos T1 y T3: TLS no movió la latencia ni el límite, que siguió en
    Postgres [E-307] [E-308]. T2 falla, pero el escalón de 600 rps está en el
    borde: el caso escalado no lo completó por 63 timeouts entre 30.000
    requests [E-138]. TLS no cambia el trabajo de Postgres, así que no le
    atribuimos la diferencia.

    T4 a T6 fallan por el nodo 0. T6 suponía que el nodo con más requests
    gasta más CPU. A 400 rps pasó lo contrario: el nodo 0 atendió 175 rps
    con 23,5 % de CPU, y el nodo 2, 225 con 13,1 % [E-160] [E-311].
  ],
  compromiso: [
    El primer request en HTTP viaja en claro. Un `POST /exchange` al puerto 80
    manda su body, con el `dni`, antes de recibir el `308` [E-158]. HSTS evita
    ese request sólo en clientes que lo implementan y ya visitaron el sitio.

    El certificado autofirmado no autentica al servidor. Un cliente tiene que
    recibirlo por otro canal o desactivar la validación, como hace Artillery.
    Un certificado de una CA necesita un dominio propio, que no tenemos.

    El certificado vence a los 30 días [E-157] y está atado al FQDN, que
    cambia cada vez que `platform` recrea la IP pública. Cada vez hay que
    generarlo y redesplegarlo. La clave privada vive en cada nodo y en la
    máquina del operador.

    El cifrado corre en el event loop del único proceso de cada nodo, junto
    con los requests. Con conexiones reutilizadas, su costo no se distingue
    en el nodo 2. No medimos una carga con una conexión nueva por request.
  ],
)
