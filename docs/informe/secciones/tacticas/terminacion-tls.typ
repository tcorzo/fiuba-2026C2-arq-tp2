#import "../../plantilla.typ": *

#tactica(
  nombre: "Terminación TLS",
  qa: ("Seguridad",),
  base: "measured/scaled",
  commit: "measured/db-pool-cap-base",
  problema: [
    En el caso escalado, el tráfico entre el cliente y los nodos viaja sin
    cifrar. El load balancer recibe HTTP en el puerto 80 y reenvía TCP al 3000
    de cada nodo [E-217] [E-19]. Cada `POST /exchange` lleva en el body el
    `dni` del cliente [E-77], legible para cualquiera en el camino.

    En el TP 1, nginx terminaba TLS (H-38) [E-38]. En este despliegue no hay
    nginx, y el load balancer trabaja en la capa 4: reenvía TCP sin leerlo
    [E-217].
  ],
  prediccion: [
    Esperábamos que TLS no moviera la latencia que mide Artillery ni el
    componente que limita, y que su costo apareciera en la CPU de los nodos.
    El handshake ocurre una vez por conexión, y `pool-ramp` reutiliza las
    conexiones entre requests. Commiteamos las predicciones, T1 a T6, en
    #sha("19e050d"), antes de medir [E-154]. Las escribimos para una ejecución
    desde otro generador, que descartamos porque no corrió desde la
    estación cableada. T1 compara la diferencia sobre la latencia de base de cada
    generador, así que la evaluamos igual contra esta ejecución.
  ],
  implementacion: [
    Node termina TLS en el mismo proceso que atiende los requests, con
    `node:https`, sin componentes nuevos
    (#codigo("node/server.js", "18-31", en: "3ee54a4")). El servidor HTTPS
    escucha en el 3443, acepta TLS 1.2 o superior y agrega
    `Strict-Transport-Security` a cada respuesta. Otro servidor, en el 3080,
    sólo responde `308` hacia la misma URL en HTTPS
    (#codigo("node/transport.js", "19-30", en: "3ee54a4")). Usamos `308` y no
    `301` porque conserva el método y el body: un `POST /exchange` redirigido
    sigue siendo un `POST`.

    pm2 ejecuta el proceso como `azureuser`, que no puede abrir puertos por
    debajo de 1024. Por eso el load balancer traduce 443 → 3443 y 80 → 3080, y
    el probe consulta el 3443 [E-155] [E-156]. El NSG de los nodos abre el
    3443 y el 3080 y cierra el 3000
    (#codigo("infra/modules/network/main.tf", "74-91", en: "3ee54a4")).

    El certificado es autofirmado, ECDSA P-256, emitido para el FQDN del load
    balancer. `mise run app:certs` lo genera en `certs/`, un directorio fuera
    de git (#codigo("mise.toml", "280-301", en: "3ee54a4")). Ansible copia el
    par a cada nodo, con la clave privada en modo `0600`
    (#codigo("ansible/vmss_deploy.yml", "16-33", en: "3ee54a4")). Artillery
    apunta a `https://` sin validar el certificado, igual que en el TP 1.

    Con la táctica desplegada, `curl` negocia TLS 1.3, valida el certificado y
    recibe `200` con HSTS [E-157]. `openssl s_client` confirma el nombre del
    servidor [E-159]. Un `POST /exchange` al puerto 80 recibe `308` con
    `Location` en `https://` [E-158].
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
      caption: [Caso escalado y TLS, desde la misma estación y con
        `pool-ramp`. Mediana y p95: rango de los intervalos de 10 s enteros de
        cada escalón. Respuestas por segundo y CPU: promedio de Datadog en los
        40 s centrales del escalón. La latencia de base es de 169 ms con HTTP
        y con HTTPS [E-90] [E-303].],
    ) <tabla-tls>

    Hasta 400 rps, la latencia no cambió. Escalón por escalón, la mediana con
    TLS quedó a lo sumo 10,9 ms por encima de la del caso escalado. La latencia
    de base varía 15 ms entre requests [E-303]. La CPU de los nodos sí subió,
    casi toda en uno de los dos:

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
          [Escalado, nodo~0], [189 / 11,3 %], [273 / 15,7 %], [5,8 %], [4,5 ms],
          [Escalado, nodo 1], [211 / 15,6 %], [295 / 20,7 %], [7,0 %], [5,3 ms],
          [TLS, nodo~0], [175 / 23,5 %], [300 / 31,2 %], [10,4 %], [14,8 ms],
          [TLS, nodo~2], [225 / 13,1 %], [302 / 17,2 %], [5,7 %], [2,5 ms],
        )
      },
      caption: [Requests por segundo que atendió cada nodo y su CPU, promedio
        de los 40 s centrales del escalón [E-141] [E-142] [E-143] [E-160]
        [E-311] [E-161].],
    ) <tabla-tls-nodos>

    A 600 rps, cada nodo atendió unos 300 rps. El nodo~2 usó 17,2 % de CPU, lo
    mismo por request que los nodos sin TLS. El nodo~0 usó 31,2 %, casi el
    doble. Los handshakes no explican esa diferencia: cada nodo aceptó unas
    3.700 conexiones [E-162], menos que sin TLS [E-163].

    No identificamos qué consumió la CPU de más en el nodo~0, porque la
    evidencia registra la CPU total de cada nodo y no la de cada proceso. En el
    nodo~2, el costo de TLS por request queda dentro de la diferencia que ya
    había entre los dos nodos sin TLS.

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

    T1 y T3 se cumplieron: la latencia no cambió, y Postgres siguió como límite
    con hasta 91,8 % de CPU y 16 sesiones esperando un lock [E-307] [E-308].
    T2 falló por un escalón. El caso escalado no completó el de 600 rps por 63
    timeouts en 30.000 requests [E-138]. Como TLS no cambia el trabajo de
    Postgres, no le atribuimos esa diferencia.

    T4, T5 y T6 fallaron por el nodo~0. T6 suponía que el nodo con más
    requests usaría más CPU, y a 400 rps pasó lo contrario. El nodo~0 atendió
    175 rps con 23,5 % de CPU, y el nodo~2, 225 rps con 13,1 % [E-160]
    [E-311].
  ],
  compromiso: [
    La redirección no protege el primer request. Si un cliente manda
    `POST /exchange` al puerto 80, el `dni` ya cruzó internet sin cifrar cuando
    llega el `308` [E-158]. HSTS evita que se repita, pero sólo en clientes que
    lo respetan y que ya recibieron una respuesta por HTTPS.

    Un certificado autofirmado cifra el canal, pero no autentica al servidor.
    El cliente tiene que confiar en él por otro medio o desactivar la
    validación, como hace Artillery. Un certificado de una CA requiere un
    dominio propio, que no tenemos.

    El certificado vence a los 30 días [E-157] y está emitido para el FQDN,
    que cambia cada vez que `platform` recrea la IP pública. En los dos casos
    hay que generarlo y desplegarlo de nuevo. La clave privada queda en cada
    nodo y en la máquina del operador.

    El cifrado corre en el event loop, sobre la única vCPU del nodo, junto con
    los requests. Con conexiones reutilizadas, su costo no se notó en el nodo~2. No medimos una carga que abra una conexión nueva por request.
  ],
)
