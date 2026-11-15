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

=== Prefijo de métricas reservado por Datadog

En #sha("02e712f"), el agente mantuvo el prefijo `exchange.` que las métricas
tenían en el TP 1. Datadog reserva `exchange.*` para su integración con
Microsoft Exchange Server, y el `apply` del stack `observability` falló en las
tres distribuciones: `Cannot configure tags on metric because metric is an
integration metric`.

Sin esa configuración, Datadog no calcula los percentiles de esas métricas. En
#sha("ca6a3f3") cambiamos el prefijo a `arvault.`, y el siguiente `apply`
terminó sin errores.
