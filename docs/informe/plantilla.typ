// Plantilla del informe — TP2 Arquitectura del Software (75.73 / TB034)
//
// Uso desde informe.typ:
//   #import "plantilla.typ": *
//   #show: informe.with(titulo: "...", integrantes: (...), ...)
//
// Lo que exige el enunciado y esta plantilla controla:
//   - A4, fuente de 11 pt, márgenes de 2,5 cm.
//   - Cuerpo de 30 páginas como máximo. La carátula, el índice general y el
//     índice de evidencia no cuentan. `mise run report:check` lo verifica.
//   - Toda afirmación cita evidencia como `[E-NN]`. Cada ID se declara en
//     `evidencia.yml` y sale en el índice de evidencia. Un ID que no está
//     declarado sale en rojo, y `mise run report:check` falla.

#let acento = rgb("#37474F")
#let aviso = rgb("#B0883B")
#let suave = rgb("#ECEFF1")

#let faltante(texto) = text(style: "italic", fill: red)[#texto]

// ─────────────────────────────────────────────────────────────
// Marcador visible de contenido por escribir.
// Se ve en el PDF para que no se escape nada sin completar. El enunciado no
// acepta secciones sin desarrollar: `mise run report:check` falla mientras
// quede alguno.
// ─────────────────────────────────────────────────────────────
#let pendiente(body) = {
  [#metadata("pendiente") <pendiente>]
  block(
    width: 100%,
    fill: rgb("#FFF8E1"),
    stroke: (left: 3pt + aviso),
    inset: 10pt,
    radius: 2pt,
    breakable: false,
  )[
    #text(weight: "bold", size: 9pt, fill: aviso)[PENDIENTE]
    #v(3pt, weak: true)
    #body
  ]
}

// ─────────────────────────────────────────────────────────────
// Referencias al repositorio.
//
//   Medido sobre #commit("measured/1-node").
//   La salida corresponde a #sha("27c33e7").
//   Los cambios de la táctica: #diff("27c33e7", "measured/tactic-cache").
//   La regla del load balancer (#codigo("infra/node.tf", "60-72", en: "0dcec46")).
//
// `ref` es un tag, una rama o un SHA; sale como enlace a ese árbol en GitHub.
// `#codigo` exige `en:`: una cita contra `main` cambia de líneas cada vez que
// `main` avanza, y la verificación por muestreo la contrasta contra el
// repositorio. GitHub marca un solo rango, así que con "70,85" el enlace marca
// el primero. `etiqueta` reemplaza el texto que se ve, `ruta:lineas` por
// defecto.
//
// Estos enlaces no reemplazan a `[E-NN]`: una afirmación cita su evidencia
// con el ID, y el índice de evidencia dice dónde está.
// ─────────────────────────────────────────────────────────────
#let repositorio = "https://github.com/tcorzo/fiuba-2026C2-arq-tp2"
#let repositorio-tp1 = "https://github.com/tcorzo/fiuba-2026C2-arq-tp1"

#let commit(ref, repo: repositorio) = link(repo + "/tree/" + ref, raw(ref))

// El parámetro `commit` de `#tactica` tapa a la función del mismo nombre.
#let enlace-commit = commit

#let sha(hash, repo: repositorio) = {
  assert(
    type(hash) == str and hash.match(regex("^[0-9a-f]{7,40}$")) != none,
    message: "sha: se esperaba un SHA de 7 a 40 dígitos hexadecimales, no "
      + repr(hash),
  )
  link(repo + "/tree/" + hash, raw(hash))
}

#let diff(desde, hasta, texto: [diff], repo: repositorio) = link(
  repo + "/compare/" + desde + "..." + hasta,
  texto,
)

#let codigo(ruta, lineas, en: none, etiqueta: auto, repo: repositorio) = {
  assert(
    en != none,
    message: "codigo: falta `en:` (un SHA o un tag) para " + ruta,
  )
  let rango = str(lineas).split(",").first().split("-")
  let ancla = "#L" + rango.first() + if rango.len() > 1 { "-L" + rango.last() }
  link(
    repo + "/blob/" + en + "/" + ruta + ancla,
    raw(if etiqueta == auto { ruta + ":" + str(lineas) } else { etiqueta }),
  )
}

// ─────────────────────────────────────────────────────────────
// Evidencia.
//
// Se declara en `evidencia.yml`, una entrada por ID:
//
//   - id: E-01
//     descripcion: Reporte de Artillery, 1 nodo, escenario `exchange-ramp`
//     ubicacion: perf/results/1-nodo/exchange-ramp.json
//   - id: E-04
//     descripcion: Manejo del timeout de ARCA
//     ubicacion: node/app.js
//     lineas: "40-55"
//     commit: 55a2922
//
// `commit` fija la ubicación a ese commit, y es obligatorio con `lineas`: una
// cita por líneas contra `main` se corre cada vez que `main` avanza, como con
// `#codigo`. El índice enlaza el archivo en ese commit.
//
// En la prosa se cita escribiendo el ID entre corchetes, como pide el
// enunciado: `La mediana sube a 180 ms [E-01].` La regla `citar-evidencia` de
// `informe` enlaza la cita a su fila del índice. Un ID que no está en
// `evidencia.yml` sale en rojo.
//
// `descripcion` admite markup de Typst (`código`, *negrita*). `ubicacion` es
// una ruta desde la raíz del repositorio; `mise run report:check` falla si no
// existe (en `commit`, si lo tiene) o si `lineas` pasa del final del archivo.
// ─────────────────────────────────────────────────────────────
#let evidencia = yaml("evidencia.yml")
#let ids-evidencia = evidencia.map(e => e.id)

#let citar-evidencia(it) = {
  let id = it.text.slice(1, -1)
  [#metadata(id) <cita-evidencia>]
  if id in ids-evidencia { link(label(id), it) } else {
    text(fill: red, weight: "bold", it)
  }
}

#let indice-evidencia() = {
  // `report:check` lee esta marca para verificar que cada ubicación existe.
  [#metadata(evidencia) <evidencia>]

  heading(numbering: none)[Índice de evidencia]

  set text(size: 9pt)
  table(
    columns: (auto, 1.2fr, 1fr),
    align: (left + top, left + top, left + top),
    inset: (x: 6pt, y: 5pt),
    stroke: (x, y) => (
      bottom: if y == 0 { 0.8pt + acento } else { 0.3pt + rgb("#CFD8DC") },
    ),
    table.header([*ID*], [*Descripción*], [*Ubicación en el repositorio*]),
    ..evidencia
      .map(e => (
        [#raw(e.id) #label(e.id)
          // Un ID declarado que nadie cita es evidencia que no respalda nada.
          #context if e.id not in query(<cita-evidencia>).map(m => m.value) {
            linebreak()
            faltante[sin citar]
          }],
        eval(e.descripcion, mode: "markup"),
        if "commit" in e {
          // Fijada a un commit: el enlace y las líneas no se corren cuando
          // `main` avanza.
          let ancla = if "lineas" in e {
            let rango = str(e.lineas).split(",").first().split("-")
            "#L" + rango.first() + if rango.len() > 1 { "-L" + rango.last() }
          } else { "" }
          link(
            repositorio + "/blob/" + e.commit + "/" + e.ubicacion + ancla,
            raw(e.ubicacion),
          )
          if "lineas" in e [, líneas #e.lineas]
          [, en #sha(e.commit)]
        } else {
          raw(e.ubicacion)
          if "lineas" in e [, líneas #e.lineas]
        },
      ))
      .flatten(),
  )
}

// ─────────────────────────────────────────────────────────────
// Tabla de resultados clave (resumen ejecutivo).
//
//   #tabla-resultados((
//     (caso: [1 nodo], nodos: 1, escenario: `exchange-ramp`,
//      throughput: [42 req/s], mediana: [180 ms], p95: [410 ms],
//      errores: [0,2 %], limitante: [CPU del nodo], evidencia: "E-01"),
//   ))
//
// Una fila por caso medido: 1 nodo, escalado y cada táctica. Es la referencia
// de la defensa en el final, así que cada número sale de su reporte crudo.
// Todos los campos son obligatorios; el que falte sale en rojo.
// ─────────────────────────────────────────────────────────────
#let columnas-resultados = (
  ("caso", [Caso]),
  ("nodos", [Nodos]),
  ("escenario", [Escenario]),
  ("throughput", [Throughput sostenido]),
  ("mediana", [Latencia mediana]),
  ("p95", [Latencia p95]),
  ("errores", [Errores]),
  ("limitante", [Componente limitante]),
  ("evidencia", [Evidencia]),
)

#let tabla-resultados(filas) = {
  set text(size: 8pt)
  set par(justify: false)
  table(
    columns: (auto,) * columnas-resultados.len(),
    align: left + horizon,
    inset: (x: 4pt, y: 4pt),
    stroke: (x, y) => (
      bottom: if y == 0 { 0.8pt + acento } else { 0.3pt + rgb("#CFD8DC") },
    ),
    table.header(..columnas-resultados.map(((_, t)) => text(
      weight: "bold",
      t,
    ))),
    ..filas
      .map(f => columnas-resultados.map(((k, _)) => {
        let v = f.at(k, default: none)
        if v == none { faltante[?] } else if k == "evidencia" {
          // Pasa por la misma regla que una cita en la prosa.
          "[" + v + "]"
        } else [#v]
      }))
      .flatten(),
  )
}

// ─────────────────────────────────────────────────────────────
// Predicción contra resultado.
//
//   #prediccion(
//     metrica: [Latencia p95 de `POST /exchange`],
//     predicho: [≤ 450 ms],
//     observado: [512 ms],
//     evidencia: "E-07",
//   )
//
// La predicción se copia de `perf/predicciones.md`, que se commitea ANTES que
// los resultados. El texto que sigue explica la diferencia.
// ─────────────────────────────────────────────────────────────
#let prediccion(
  metrica: none,
  predicho: none,
  observado: none,
  evidencia: none,
) = block(
  width: 100%,
  fill: suave,
  inset: (x: 9pt, y: 7pt),
  radius: 2pt,
  breakable: false,
)[
  #set text(size: 9.5pt)
  #grid(
    columns: (auto, 1fr),
    row-gutter: 5pt,
    column-gutter: 10pt,
    text(weight: "bold")[Métrica],
    if metrica == none { faltante[a completar] } else { metrica },

    text(weight: "bold")[Predicción],
    if predicho == none { faltante[a completar] } else { predicho },

    text(weight: "bold")[Observado],
    if observado == none { faltante[sin medir] } else { observado },

    text(weight: "bold")[Evidencia],
    if evidencia == none { faltante[sin evidencia] } else {
      "[" + evidencia + "]"
    },
  )
]

// ─────────────────────────────────────────────────────────────
// Una táctica superadora. Va en `tacticas/<táctica>.typ`, una por archivo.
//
//   #tactica(
//     nombre: "Cache",
//     qa: ("Performance",),
//     base: "27c33e7",
//     commit: "measured/tactic-cache",
//     problema: [Qué se observó, con su evidencia.],
//     prediccion: [La hipótesis numérica, copiada de perf/predicciones.md.],
//     implementacion: [Qué se cambió en el código, Terraform o Ansible.],
//     resultados: [La medición y su comparación con la predicción.],
//     compromiso: [Qué atributo se resigna a cambio.],
//   )
//
// Las seis partes son las que pide el enunciado para cada táctica. `base` es
// el commit del "antes" y `commit` el del "después": un SHA o un tag. Todos los
// campos son obligatorios; el que falte sale en rojo.
// ─────────────────────────────────────────────────────────────
#let tactica(
  nombre: "",
  qa: (),
  base: "",
  commit: "",
  problema: none,
  prediccion: none,
  implementacion: none,
  resultados: none,
  compromiso: none,
) = {
  let enlace-ref(ref) = if ref.match(regex("^[0-9a-f]{7,40}$")) != none {
    sha(ref)
  } else { enlace-commit(ref) }

  heading(level: 2)[#if nombre == "" { faltante("sin nombre") } else { nombre }]

  block(
    width: 100%,
    fill: suave,
    inset: (x: 9pt, y: 7pt),
    radius: 2pt,
    breakable: false,
  )[
    #set text(size: 9.5pt)
    #grid(
      columns: (auto, 1fr),
      row-gutter: 5pt,
      column-gutter: 10pt,
      text(weight: "bold")[QA objetivo],
      if qa.len() == 0 { faltante("a completar") } else { qa.join(", ") },

      text(weight: "bold")[Antes],
      if base == "" { faltante("a completar") } else { enlace-ref(base) },

      text(weight: "bold")[Después],
      if commit == "" { faltante("sin medir") } else {
        enlace-ref(commit)
        if base != "" [ (#diff(base, commit))]
      },
    )
  ]

  let seccion(titulo, contenido) = {
    heading(level: 3, numbering: none, outlined: false, titulo)
    if contenido == none { faltante("a completar") } else { contenido }
  }

  seccion([Problema observado], problema)
  seccion([Predicción], prediccion)
  seccion([Implementación], implementacion)
  seccion([Resultados], resultados)
  seccion([Tradeoffs], compromiso)
}

// ─────────────────────────────────────────────────────────────
// Portada
// ─────────────────────────────────────────────────────────────
#let portada(
  titulo: "",
  subtitulo: "",
  materia: "",
  catedra: "",
  cuatrimestre: "",
  grupo: "",
  integrantes: (),
  fecha: "",
  repo: "",
) = {
  set page(numbering: none)
  set align(center)

  v(3cm)

  text(size: 13pt, fill: acento)[#materia]
  linebreak()
  text(size: 11pt, fill: acento)[#catedra · #cuatrimestre]

  v(1.6cm)

  line(length: 45%, stroke: 0.6pt + acento)
  v(6pt)
  text(size: 24pt, weight: "bold")[#titulo]
  if subtitulo != "" {
    v(8pt)
    text(size: 13pt, style: "italic")[#subtitulo]
  }
  v(6pt)
  line(length: 45%, stroke: 0.6pt + acento)

  v(1.8cm)

  text(size: 13pt, weight: "bold")[#grupo]

  v(8pt)

  table(
    columns: (auto, auto),
    align: (left, right),
    stroke: none,
    inset: (x: 10pt, y: 4pt),
    ..integrantes.map(i => (i.nombre, raw(i.padron))).flatten(),
  )

  v(1fr)

  set align(center)
  text(size: 10pt)[Fecha de entrega: #fecha]
  if repo != "" {
    linebreak()
    text(size: 10pt)[Repositorio: #link(repo)[#repo]]
  }

  v(1cm)
}

// ─────────────────────────────────────────────────────────────
// Límite de extensión.
//
// El cuerpo va desde la primera página después del índice general hasta la
// última antes del índice de evidencia. `informe` marca ambos extremos;
// `mise run report:check` lee las marcas y falla por encima del límite.
// ─────────────────────────────────────────────────────────────
#let limite-paginas = 30

#let paginas-cuerpo() = {
  let inicio = query(<inicio-cuerpo>)
  let fin = query(<fin-cuerpo>)
  if inicio.len() == 0 or fin.len() == 0 { return none }
  fin.first().location().page() - inicio.first().location().page() + 1
}

// ─────────────────────────────────────────────────────────────
// Documento
// ─────────────────────────────────────────────────────────────
#let informe(
  titulo: "",
  subtitulo: "",
  materia: "",
  catedra: "",
  cuatrimestre: "",
  grupo: "",
  integrantes: (),
  fecha: "",
  repo: "",
  doc,
) = {
  set document(title: titulo, author: integrantes.map(i => i.nombre))

  // El enunciado fija A4, 11 pt y márgenes de 2,5 cm.
  set page(paper: "a4", margin: 2.5cm)
  set text(
    font: ("Libertinus Serif", "Liberation Serif"),
    size: 11pt,
    lang: "es",
  )
  set par(justify: true, leading: 0.68em, spacing: 1.1em)
  // Se numeran los tres primeros niveles; del cuarto en adelante, los títulos
  // salen sin número y fuera del índice.
  set heading(numbering: (..n) => if n.pos().len() <= 3 {
    numbering("1.1", ..n)
  })

  show raw: set text(font: "DejaVu Sans Mono", size: 9pt)
  show regex("\[E-\d{2,3}\]"): citar-evidencia
  show link: it => text(fill: acento, it)
  show heading.where(level: 1): it => {
    v(0.6em)
    text(size: 16pt, it)
    v(0.3em)
  }
  show heading.where(level: 2): it => {
    v(0.4em)
    text(size: 13pt, it)
    v(0.2em)
  }
  show heading.where(level: 3): it => {
    v(0.3em)
    text(size: 11.5pt, it)
    v(0.15em)
  }
  show heading.where(level: 4): it => {
    v(0.25em)
    text(size: 10.5pt, it)
    v(0.1em)
  }
  show figure.caption: set text(size: 9.5pt)

  portada(
    titulo: titulo,
    subtitulo: subtitulo,
    materia: materia,
    catedra: catedra,
    cuatrimestre: cuatrimestre,
    grupo: grupo,
    integrantes: integrantes,
    fecha: fecha,
    repo: repo,
  )

  pagebreak()

  outline(title: [Índice], depth: 3)

  pagebreak()

  set page(numbering: "1")
  counter(page).update(1)

  [#metadata(none) <inicio-cuerpo>]
  doc
  [#metadata(none) <fin-cuerpo>]

  // El índice de evidencia no cuenta para el límite: va en su propia página,
  // sin numeración de cuerpo.
  pagebreak()
  set page(numbering: "I")
  counter(page).update(1)
  indice-evidencia()

  // `report:check` lee el total desde acá.
  context [#metadata(paginas-cuerpo()) <paginas-cuerpo>]
}
