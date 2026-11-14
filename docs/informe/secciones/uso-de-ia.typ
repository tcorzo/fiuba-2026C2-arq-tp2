#import "../plantilla.typ": *

= Uso de herramientas de IA

== Herramientas

#pendiente[
  Qué herramientas se usaron y para qué partes del trabajo: código, Terraform,
  Ansible, escenarios de carga, redacción, análisis.
]

== Cómo se registró

Cada commit producido con asistencia de un agente lleva el trailer
`Co-Authored-By: Claude …`. El registro es verificable sobre el propio
historial del repositorio:

```sh
git log --format='%h %s' --grep='Co-Authored-By: Claude'
```

== Usos concretos

#table(
  columns: (auto, 1fr),
  inset: (x: 6pt, y: 5pt),
  stroke: 0.4pt + suave,
  align: (left, left),
  table.header([*Tarea*], [*Qué hizo el agente y qué hicimos nosotros*]),

  [Tooling del repositorio],
  [Tareas de `mise`, hooks de pre-commit, workflows de CI, la plantilla de este
    informe y `CLAUDE.md`, adaptados desde el TP 1. No es contenido del informe.],

  [Estado en HCP Terraform y outputs (issue \#1)],
  [El agente reemplazó los `local-exec` por outputs que los scripts leen con
    `terraform output`. También escribió el stack `infra/bootstrap`: workspaces,
    variables e identidad OIDC de Azure. Nosotros elegimos la ejecución remota,
    revisamos el diff y aplicamos el bootstrap.],

  [Tamaño de las VM],
  [El primer `apply` falló con `SkuNotAvailable` para `Standard_B1s`. El agente
    consultó los tamaños y la cuota de la suscripción en `eastus2` con `az` y
    propuso `Standard_F1als_v7`. Nosotros revisamos el cambio y aplicamos.],

  [Site de Datadog],
  [Una cuenta del grupo está en `us5.datadoghq.com`. El agente revisó el repo y
    encontró el site US1 fijo en Ansible y en Artillery. Propuso leerlo de
    `DATADOG_SITE`, con US1 por defecto. Nosotros descartamos el default: una key
    enviada al site equivocado pierde los datos sin error visible. La variable
    quedó obligatoria.],

  [Región y storage],
  [El agente diagnosticó que la app no escuchaba porque le faltaba Postgres.
    Encontró que la suscripción no puede crear PostgreSQL Flexible Server en
    `eastus2`. Un `validate` de ARM dio `Succeeded` y era engañoso: lo confirmó
    una creación real, que falló. Probó y borró los recursos en `centralus`.
    Nosotros decidimos mover la región.],

  [Postgres en Terraform],
  [El agente escribió el módulo `database`: subnet delegada, zona DNS privada y
    servidor B1ms sin acceso público. Corrió un `plan` remoto, sin aplicar.
    tflint pidió `prevent_destroy`. Lo descartamos porque `mise run down` destruye
    `foundation` en cada sesión.],

  [App y deploy contra Postgres],
  [El agente pasó `databaseUrl` por `config.js` y sumó al deploy la siembra y
    una espera a `GET /`. Encontró que `node/zip` no empaquetaba `state/`, que la
    siembra necesita. Lo probó contra un Postgres 18 local en Docker.],

  [Integración con ARCA (issue \#14)],
  [El agente escribió el adaptador de ARCA con `fetch` y timeout, sin
    reintentos. Cada exchange valida el `dni` antes de mover fondos. Escribió
    tests contra un ARCA falso y sumó el `dni` aleatorio a los escenarios.
    Nosotros decidimos no reintentar y revisamos el diff.],

  [Métricas del servicio en Datadog],
  [El agente encontró, en el nodo y bajo carga, que la app mandaba sus
    métricas a `graphite`, un nombre que no resuelve en Azure. Apuntó la app al
    agente de Datadog y pasó la ruta y el resultado a tags. Escribió tests que
    escuchan los datagramas por UDP. Nosotros revisamos el diff.],

  [Dashboard de Datadog en Terraform],
  [El agente pasó el dashboard a un stack de Terraform, `observability`, con los
    percentiles de las tres distribuciones. Encontró que el widget de latencia
    por ruta del cliente leía métricas que ningún escenario publica. Nosotros
    revisamos el diff.],
)

== Propuestas incorrectas

=== Destroy bloqueado por un output nuevo

En #sha("21c8367"), el agente agregó `databaseUrl` al output `app_config` de
`platform`. El valor sale de `database_url`, un output nuevo de `foundation`.

El agente propuso aplicar el cambio con `mise run down` y después `mise run up`.
Advirtió que `platform` no podía planificar sin `database_url` aplicado. No previó
que el destroy tiene el mismo problema.

El state de `foundation` en Azure era anterior al cambio y no tenía
`database_url`. Por eso, `mise run down` falló en el destroy de `platform` con
`Unsupported attribute`. Lo reprodujimos con un plan de destroy, sin destruir
nada [E-01].

En su lugar, destruimos con el código que creó esa infraestructura, el commit
#sha("7d6e8c3"). Después aplicamos la branch nueva con `mise run up`.

=== Prefijo de métricas reservado por Datadog

En #sha("02e712f"), el agente mantuvo el prefijo `exchange.` de las métricas del
TP 1. En Graphite no había conflicto. Datadog reserva `exchange.*` para su
integración de Microsoft Exchange Server.

Lo detectó el `apply` del stack `observability`. Datadog rechazó la configuración
de tags de las tres distribuciones: `Cannot configure tags on metric because
metric is an integration metric`. Sin esa configuración, no hay percentiles.

El agente confirmó la causa en el `metadata.csv` de la integración. En
#sha("ca6a3f3"), cambiamos el prefijo a `arvault.`. El siguiente `apply` terminó
sin errores.

=== Orden de aplicación incompleto

El agente indicó aplicar `observability` después de ver `exchange.http.duration`
en Datadog. Ese orden no alcanzaba. La API rechaza los tags de una métrica que
todavía no recibió datos.

El primer `apply` falló en las tres distribuciones. El agente atribuyó la falla a
la falta de un exchange. Al revisar el state de HCP Terraform, vio que la
infraestructura estaba destruida y que ninguna métrica había llegado.

Separamos el dashboard de los percentiles en #sha("e268f46"). Documentamos el
orden verificado en `docs/infra/overview.md`.
