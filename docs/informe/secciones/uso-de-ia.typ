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
