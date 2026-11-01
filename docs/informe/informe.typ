#import "plantilla.typ": *

#show: informe.with(
  titulo: "arVault en la nube",
  subtitulo: "Despliegue del servicio de cambio de monedas sobre Azure",
  materia: "Arquitectura del Software (75.73 / TB034)",
  catedra: "FIUBA",
  cuatrimestre: "2do cuatrimestre 2026",
  grupo: "GaudiFollowers",
  integrantes: (
    (nombre: "Tomás Corzo", padron: "110130"),
    (nombre: "Matías Ferrero", padron: "109886"),
    (nombre: "Sebastián Kraglievich", padron: "109038"),
    (nombre: "Franco Ricciardo Calderaro", padron: "109907"),
  ),
  fecha: "19 de noviembre de 2026",
  repo: "https://github.com/tcorzo/fiuba-2026C2-arq-tp2",
)

// El orden y los títulos son los que fija el enunciado (README.md, "Formato y
// extensión"). El índice de evidencia lo agrega la plantilla al final.

#include "secciones/resumen.typ"

#include "secciones/entorno.typ"

#include "secciones/punto-de-partida.typ"

#include "secciones/arquitectura.typ"

#include "secciones/compose-vs-nube.typ"

#include "secciones/arca.typ"

#include "secciones/un-nodo.typ"

#include "secciones/escalado.typ"

#include "secciones/tacticas.typ"

#include "secciones/descartadas.typ"

#include "secciones/conclusiones.typ"

#include "secciones/uso-de-ia.typ"
