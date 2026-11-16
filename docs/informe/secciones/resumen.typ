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
  (
    caso: [Escalado],
    nodos: 2,
    escenario: [rampa del TP 1 con pool (pool-ramp)],
    throughput: [400 rps],
    mediana: [172,5 a 175,9 ms],
    p95: [944 a 983 ms],
    errores: [sin timeouts; 9,9 % de 502 de ARCA],
    limitante: [Postgres, por CPU, con más conexiones que 1 nodo],
    evidencia: "E-138",
  ),
  (caso: [Táctica], nodos: none),
  (
    caso: [Tope de conexiones: base (10 por nodo)],
    nodos: 2,
    escenario: [rampa del TP 1 con pool (pool-ramp), por HTTPS],
    throughput: [600 rps; 584,9 respuestas/s a 800 rps],
    mediana: [179,5 a 478,3 ms],
    p95: [963 a 2.780 ms],
    errores: [sin timeouts; 9,8 % de 502 de ARCA],
    limitante: [Postgres, por CPU, con 16 esperas `Lock`],
    evidencia: "E-304",
  ),
  (
    caso: [Tope de conexiones (5 por nodo)],
    nodos: 2,
    escenario: [rampa del TP 1 con pool (pool-ramp), por HTTPS],
    throughput: [600 rps; 690,5 respuestas/s a 800 rps],
    mediana: [183,1 a 257,3 ms],
    p95: [983 a 1.408 ms],
    errores: [sin timeouts; 9,9 % de 502 de ARCA],
    limitante: [Postgres, por CPU, con el generador saturado desde 600 rps],
    evidencia: "E-324",
  ),
))
