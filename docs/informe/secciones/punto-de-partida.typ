#import "../plantilla.typ": *

= Punto de partida desde el TP 1

El servicio sale del TP 1, en el commit #sha("f6d14f1", repo: repositorio-tp1).
Copiamos `app/` a `node/` sin cambios de lógica. En el commit #sha("426e2fd"),
el diff entre los dos directorios cambia la lectura de la configuración, agrega
`GET /` y toca comentarios [E-02]. Después, la integración con ARCA cambió
`node/` (sección 6).

En ese mismo commit, la suite de tests del TP 1 corre sobre `node/`. Pasan 111
tests y ninguno falla [E-03]. Los tests de Postgres no corren sin una base, así
que esta suite no verifica el adaptador de Postgres [E-03].

El TP 1 tenía 27 tácticas. Las clasificamos según dónde estaba implementada
cada una: en el código, en Docker Compose o en nginx. Según esa ubicación, una
táctica se traslada sin cambios, cambia de forma o deja de aplicar en Azure.

== Las tácticas del código se trasladan sin cambios

Estas tácticas están en `node/`. Llegaron sin cambios de lógica [E-02], y sus
tests pasan [E-03]. No dependen de Docker ni de nginx, así que el despliegue no
las afecta.

#table(
  columns: (1fr, auto),
  inset: (x: 6pt, y: 4pt),
  stroke: 0.4pt + suave,
  align: (left, left),
  table.header([*Táctica*], [*Hallazgos del TP 1*]),
  [Exception Handling], [H-01],
  [Validate Input (monedas y pares)], [H-01, H-30],
  [Reserva atómica de fondos], [H-06],
  [Validate Input (la entrada)], [H-07],
  [Fuente única de verdad], [H-08, H-29],
  [Concurrency (transferencias concurrentes)], [H-12],
  [Externalizar estado], [H-14],
  [Specialized Interfaces], [H-19],
  [Sandbox (tests en CI)], [H-20],
  [Limit Structural Complexity], [H-21],
  [Refactoring de estado y de la dependencia de transferencia], [H-22, H-23],
  [Validate Input (tipos)], [H-31, H-44],
  [Tailor Interface], [H-34],
  [Lazy Loading], [H-35],
)

Externalizar estado (H-14) habilita el caso escalado. El servicio no guarda
estado propio, así que cualquier nodo del VMSS atiende cualquier request.

== Las tácticas de infraestructura cambian de forma

Estas tácticas estaban implementadas en Docker Compose. En Azure, un servicio
administrado o un recurso de Terraform cumple la misma función.

*External Database y Persistent Storage (H-04, H-05, H-09, H-10, H-11, H-26,
H-27).* Postgres pasa a Azure Database for PostgreSQL Flexible Server, versión
18, SKU `B_Standard_B1ms` [E-04]. Azure administra el almacenamiento, así que el
volumen de Docker deja de existir.

*Horizontal Scale y Load Balancing (H-13, H-36).* Cada réplica pasa a ser un
nodo del VMSS, y el load balancer de Azure reparte el tráfico [E-05]. El VMSS
registra cada nodo en el backend pool. La cantidad de nodos está escrita a mano
en el módulo `app` de Terraform [E-05].

*Restart Policy y Healthcheck (H-03).* pm2 reinicia el proceso de Node si
termina. Lo probamos con un nodo: matamos el proceso con `kill -9`, y pm2 lo
levantó en el mismo segundo. Después, `GET /` respondió `200` a través del load
balancer [E-18].

El load balancer prueba cada nodo con un probe. El probe no declara protocolo,
y Azure usa TCP por defecto [E-05]. Un probe TCP sólo abre una conexión al
puerto 3000 y no manda ningún request HTTP. Si el puerto rechaza la conexión,
el load balancer deja de mandarle tráfico al nodo. Si el proceso se cuelga con
el puerto abierto, el probe lo da por sano y el nodo sigue recibiendo requests
que nunca responde.

== Las tácticas de nginx no se trasladan

No hay nginx en este despliegue. El load balancer de Azure trabaja en la capa 4.
Reenvía TCP del puerto 80 al 3000 y no lee HTTP [E-05]. Ningún componente
ejecuta las tres tácticas que estaban en nginx.

*Encrypt Data (H-38).* Ningún componente termina TLS. El tráfico entre el
cliente y el nodo viaja sin cifrar por internet, en HTTP al puerto 80 [E-05]
[E-19].

*Rate Limiting (H-02).* Ningún componente limita los requests por cliente.

*Limit Exposure (H-15, H-16).* El load balancer publica todas las rutas del
servicio. Eso incluye `PUT /rates`, `PUT /accounts/:id/balance`,
`GET /accounts` y `GET /log` [E-06]. A través del load balancer, `GET /accounts`
y `GET /log` responden `200`. Los dos `PUT` llegan a la app: con un body
inválido, responden su propio `400 VALIDATION_ERROR` [E-19]. Usamos un body
inválido para no cambiar datos antes de las pruebas de carga.

Desde la integración con ARCA, el log guarda el `dni` del cliente en cada
exchange que ARCA aprueba. `GET /log` y `GET /exchanges/:id` lo devuelven a
cualquier cliente [E-20].

#pendiente[
  Falta la decisión del grupo para cada una de las tres tácticas. El grupo
  puede aceptar el riesgo, reimplementarla en otro componente o elegirla como
  táctica superadora. El servicio y Application Gateway son dos componentes
  posibles. Limit Exposure es la más grave, porque cualquier cliente puede
  cambiar una tasa.
]

== Las tácticas de Docker dejan de aplicar

En este despliegue no hay contenedores para el servicio. pm2 ejecuta `node` en
cada nodo del VMSS. Estas cuatro tácticas resolvían problemas de Docker Compose:

- *Limit Exposure de la observabilidad (H-39).* No hay Graphite, StatsD ni
  cAdvisor expuestos. El agente de Datadog corre en cada nodo [E-07], y los
  nodos no tienen IP pública [E-05].
- *Limit Access (H-40).* El deploy arranca pm2 con el usuario `azureuser`, sin
  root [E-08].
- *Restrict Dependencies (H-42).* `node/zip.sh` arma el paquete del deploy con
  `*.js`, `*.json` y el estado inicial [E-09].
- *Increase Cohesion (H-46).* En este despliegue no hay archivo de Docker
  Compose.
