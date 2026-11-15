# Writing the report

How the report's prose is written. It applies to every `.typ` file under this directory. The root `CLAUDE.md` still rules on language, vocabulary, evidence and structure; this file covers style.

**The target:** es-AR as an engineer writes it for other engineers. Natural but professional, dense with facts, with no filler. A teacher reads it while checking `[E-NN]` citations at random: every sentence either states a fact, cites it, or draws a conclusion from it.

## Rules

| Rule | Instead of | Write |
|---|---|---|
| **ASD-STE100 applied to Spanish:** at most 25 words per sentence, active voice, first person plural (`medimos`, `elegimos`), literal verbs. | `La latencia fue medida por el grupo…` | `Medimos la latencia…` |
| **Short does not mean choppy.** Join facts about the same thing with a comma or a subordinate clause, as long as the sentence stays under 25 words. | `El equipo se conecta a internet por WiFi. El puerto ethernet no está conectado.` | `El equipo se conecta por WiFi, con el puerto ethernet desconectado.` |
| **Use the assignment's terms** for what the assignment asks for. The teachers grade against README.md's wording. | `speedtest-cli midió 66 Mbit/s…` | `El ancho de banda disponible, medido con speedtest-cli, es de 66 Mbit/s…` |
| **Say exactly what a measurement covers.** Name the components, not "el sistema". | `la medición incluye la red y el load balancer, pero no el trabajo del servicio` | `La medición cubre internet, el load balancer y Express en el nodo, pero no la lógica del servicio.` |
| **No vague qualifiers.** A number carries its unit and the value observed; a condition names what it excludes. | `sin otra carga sobre el sistema`, `estos 180 ms aproximados` | `antes de las pruebas de carga`, `estos 180 ms` |
| **No repetition.** Don't repeat a noun in consecutive sentences, and don't restate in prose what a table next to it already shows. | `…a través del load balancer. … detrás del load balancer.` / `Las 60 respuestas fueron 200.` under a table with `Errores: 0` | One sentence: `…a través del load balancer, que tenía un solo nodo detrás.` |
| **No redundant intensifiers.** | `este mismo equipo y esta misma red` | `este equipo y esta red` |
| **Each citation backs its own claim.** If a sentence carries two facts from two sources, it cites both. | `…había un nodo detrás del load balancer [E-70]` (E-70 is the Artillery report, it doesn't show the node count) | `…que tenía un solo nodo detrás [E-71] [E-73]` (E-73 is `az vmss list-instances`) |
| **Plain word order.** Subject, verb, object. Avoid fronted objects with a resumptive pronoun. | `Una diferencia de latencia menor que ese rango entre dos ejecuciones la tratamos como ruido.` | `Tomamos como ruido una diferencia menor entre dos ejecuciones.` |
| **es-AR number format.** Decimal comma, period for thousands, space before `%` and units. | `179.5ms`, `1,050 ms`, `70%` | `179,5 ms`, `1.050 ms`, `70 %` |

## Section 12, uso de herramientas de IA

One page at most, in three parts: tools, the areas of the project where we used them, and one or two cases where the tool was wrong. The root `CLAUDE.md`, *AI disclosure*, has what goes in each part. It is not a log of what the tool did.

## AI slop: never write these

These patterns make a text read as generated. They add words and no facts.

- **Filler connectors and openers:** `Así,` / `De esta manera,` / `En este sentido,` / `Cabe destacar que` / `Es importante mencionar que` / `Vale la pena señalar` / `A su vez,` / `Por otro lado,` (when nothing is being contrasted) / `En resumen,` / `En definitiva,`.
- **Inflated verbs and nouns:** `juega un papel fundamental`, `resulta clave`, `permite garantizar`, `en el contexto de`, `en términos de`, `a nivel de`, `llevar a cabo` (→ `hacer`), `realizar una medición` (→ `medir`).
- **Hype adjectives and adverbs:** `robusto`, `crucial`, `significativo` (unless it is a statistical claim), `notablemente`, `eficiente`, `óptimo`, `considerablemente`, `de manera efectiva`. If it matters, give the number.
- **Chained gerunds:** `…procesa el request, generando una consulta y permitiendo…`. Split into sentences with finite verbs.
- **Rhetorical structures:** `no solo X, sino también Y`, triads for rhythm (`rápido, simple y confiable`), a closing moral at the end of a paragraph, a question used as a heading or as a transition.
- **Hedging without data:** `podría deberse a`, `probablemente`, `en cierta medida`. Either it is a hypothesis (say so and say how it was tested) or it is a fact (cite it).
- **Explaining the obvious to the teachers:** what a load balancer is, what p95 means. They wrote the assignment.

## Before pushing a `.typ` edit

1. Read each paragraph aloud. If a sentence sounds like a form being filled in, join it with the next one. If it sounds like a press release, cut it.
2. Check each `[E-NN]` against the file it points to: does that file show *this* fact?
3. `typstyle -i <file>`, `mise run report`, and look at the rendered page.
4. `mise run report:check`.
