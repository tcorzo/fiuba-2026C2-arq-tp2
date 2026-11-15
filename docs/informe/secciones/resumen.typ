#import "../plantilla.typ": *

= Resumen ejecutivo

#pendiente[
  Hallazgos principales y recomendación. Extensión orientativa: 1 página.
]

#tabla-resultados((
  (
    caso: [1 nodo],
    nodos: 1,
    escenario: [sesiones (sessions.yaml)],
    throughput: [600 rps],
    mediana: [172,5 ms],
    p95: [944 ms],
    errores: [0,01 % de timeouts; 10,5 % de 502 de ARCA],
    limitante: [Pool de conexiones a Postgres (hipótesis)],
    evidencia: "E-94",
  ),
  (caso: [Escalado], nodos: 2),
  (caso: [Táctica], nodos: none),
))
