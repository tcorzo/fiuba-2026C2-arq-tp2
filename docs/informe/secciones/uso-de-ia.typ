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
)

== Propuestas incorrectas

#pendiente[
  Al menos un caso concreto en el que la herramienta propuso algo incorrecto,
  incompleto, desactualizado o inadecuado para este sistema: qué propuso, cómo
  se detectó (con evidencia `[E-NN]`) y qué se hizo en su lugar.
]
