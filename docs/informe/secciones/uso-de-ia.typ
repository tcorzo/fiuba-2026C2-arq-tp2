#import "../plantilla.typ": *

= Uso de herramientas de IA

== Herramientas

Todo el grupo usó Claude, con el modelo Claude Opus 5.5, desde Claude Code. Cada
commit hecho con su asistencia lleva el trailer `Co-Authored-By: Claude`, así
que `git log --grep='Co-Authored-By: Claude'` los lista.

== Para qué la usamos

#table(
  columns: (auto, 1fr),
  inset: (x: 6pt, y: 4pt),
  stroke: 0.4pt + suave,
  align: (left, left),
  table.header([*Parte*], [*Uso*]),
  [Infraestructura],
  [Escribir los stacks de Terraform y los playbooks de Ansible. Diagnosticar
    los errores de `apply` con `az` y la documentación de los providers.],

  [Servicio],
  [Pasar el servicio del TP 1 a Postgres e integrar ARCA y las
    métricas de Datadog, con sus tests.],

  [Mediciones],
  [Escribir los escenarios de Artillery, juntar la evidencia de
    cada configuración desplegada y analizar los resultados.],

  [Informe],
  [Redactar borradores de las secciones y escribir los diagramas
    C\&C.],

  [Tooling],
  [Tareas de `mise`, hooks de pre-commit, CI y la plantilla del
    informe.],
)

Nosotros decidimos qué hacer en cada caso. Revisamos cada diff antes del merge,
y cada afirmación del informe contra su evidencia.

== Propuestas incorrectas

=== Destroy bloqueado por un output nuevo

En #sha("21c8367"), el agente agregó `databaseUrl` al output `app_config` de
`platform`. El valor sale de `database_url`, un output nuevo de `foundation`.
Para aplicarlo, propuso `mise run down` y después `mise run up`. No previó que
el destroy de `platform` también lee ese output.

El state de `foundation` en Azure no tenía `database_url`, así que el destroy
falló con `Unsupported attribute`. Lo reprodujimos con un plan de destroy, sin
destruir nada [E-01]. Destruimos con el commit que creó esa infraestructura,
#sha("7d6e8c3"), y después aplicamos la branch nueva.

=== Prefijo de métricas reservado por Datadog

En #sha("02e712f"), el agente mantuvo el prefijo `exchange.` de las métricas del
TP 1. Datadog reserva `exchange.*` para su integración con Microsoft Exchange
Server. El `apply` del stack `observability` falló en las tres distribuciones:
`Cannot configure tags on metric because metric is an integration metric`.

Sin esa configuración, Datadog no calcula percentiles. En #sha("ca6a3f3"),
cambiamos el prefijo a `arvault.`, y el siguiente `apply` terminó sin errores.
