#import "../plantilla.typ": *

= Resumen ejecutivo

#pendiente[
  Hallazgos principales y recomendación. Extensión orientativa: 1 página.
]

#tabla-resultados((
  (
    caso: [1 nodo],
    nodos: 1,
    escenario: [rampa del TP 1 con pool (pool-ramp)],
    throughput: [600 rps],
    mediana: [179,5 a 183,1 ms],
    p95: [1.002 a 1.043 ms],
    errores: [sin timeouts; 9,8 % de 502 de ARCA],
    limitante: [Postgres, en la escritura del exchange],
    evidencia: "E-114",
  ),
  (caso: [Escalado], nodos: 2),
  (caso: [Táctica], nodos: none),
))
