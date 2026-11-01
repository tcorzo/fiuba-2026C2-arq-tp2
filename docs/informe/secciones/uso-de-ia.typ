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
)

== Propuestas incorrectas

#pendiente[
  Al menos un caso concreto en el que la herramienta propuso algo incorrecto,
  incompleto, desactualizado o inadecuado para este sistema: qué propuso, cómo
  se detectó (con evidencia `[E-NN]`) y qué se hizo en su lugar.
]
