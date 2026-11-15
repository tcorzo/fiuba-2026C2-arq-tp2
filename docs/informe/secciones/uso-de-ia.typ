#import "../plantilla.typ": *

= Uso de herramientas de IA

== Herramientas

Todo el grupo trabajó con Claude Code, sobre el modelo Claude Opus 5.5. Los
commits hechos con su ayuda llevan el trailer `Co-Authored-By: Claude`, así que
se pueden rastrear en el historial del repositorio.

== Para qué la usamos

#table(
  columns: (auto, 1fr),
  inset: (x: 6pt, y: 4pt),
  stroke: 0.4pt + suave,
  align: (left, left),
  table.header([*Parte*], [*Uso*]),
  [Infraestructura],
  [Escribir los stacks de Terraform y los playbooks de Ansible, y diagnosticar
    los errores de `apply` con `az` y la documentación de los providers.],

  [Servicio],
  [Conectar el servicio del TP 1 al Postgres de Azure, integrar ARCA y mandar
    las métricas a Datadog, con sus tests.],

  [Mediciones],
  [Escribir los escenarios de Artillery, juntar la evidencia de
    cada configuración desplegada y analizar los resultados.],

  [Informe], [Redactar borradores de las secciones y los diagramas C\&C.],

  [Tooling],
  [Armar las tareas de `mise`, los hooks de pre-commit, el CI y la
    plantilla del informe.],
)

Las decisiones fueron nuestras. Revisamos cada diff antes del merge y cada
afirmación del informe contra su evidencia.

== Propuestas incorrectas

=== Destroy bloqueado por un output nuevo

En #sha("21c8367"), el agente agregó `databaseUrl` al output `app_config` de
`platform`, a partir de `database_url`, un output nuevo de `foundation`. Para
aplicar el cambio propuso `mise run down` y después `mise run up`, sin prever
que el destroy de `platform` también lee ese output.

El state aplicado de `foundation` todavía no tenía `database_url`, y el destroy
falló con `Unsupported attribute`. Lo reprodujimos con un plan de destroy, sin
destruir nada [E-01]. Destruimos con el commit que había creado esa
infraestructura, #sha("7d6e8c3"), y recién después aplicamos la branch nueva.

=== Causa equivocada del colapso a 200 rps

La primera ejecución del caso de 1 nodo colapsó en el escalón de 200 rps: de
54.600 requests, 24.655 terminaron en timeout [E-84]. El agente, y un subagente
que revisó su análisis, atribuyeron el colapso a la tabla NAT del router y al
swap del generador de carga.

Las métricas no respaldaban esa conclusión. Desde su arranque, el nodo registró
30.570 conexiones entrantes, casi tantas como los 29.945 requests respondidos
[E-84] [E-85]. Los requests con timeout nunca llegaron al nodo.

El límite estaba en el generador. Artillery resuelve el nombre del load
balancer en cada conexión nueva, y la máquina resolvía 134 nombres por segundo
[E-86]. Con el nombre en `/etc/hosts` (#sha("32eaed5")), los escalones de
200 rps tuvieron 3 timeouts en 10.000 requests [E-87].
