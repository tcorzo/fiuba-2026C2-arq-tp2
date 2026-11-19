#import "../plantilla.typ": *

= Resumen ejecutivo

Migramos el servicio de exchanges del TP 1 a Azure, en `centralus`: un VMSS
detrás de un load balancer, PostgreSQL Flexible Server y el mock de ARCA en
Azure Container Instances (sección 4). Medimos 1 nodo, 2 nodos y dos tácticas
superadoras con la rampa del TP 1, desde un generador en Buenos Aires
(sección 2). La tabla de abajo resume cada caso.

*El límite es Postgres, no los nodos.* Con 1 nodo, el servicio sostuvo 600 rps
sin timeouts [E-114]. En toda la ejecución, la CPU de Postgres llegó a 84,5 %, y
la del nodo, a 47,4 % [E-121] [E-117].

*Escalar no aumentó el throughput.* Con 2 nodos, el último escalón completo bajó
de 600 a 400 rps [E-138]. Cada nodo abre su propio pool de 10 conexiones a la
DB, y las sesiones de Postgres que esperan un lock subieron de 8 a 12 [E-62]
[E-122] [E-146].

*Reducir la cantidad de conexiones a la DB recuperó el throughput.* Con 5
conexiones por nodo, los dos nodos atendieron 681,8 respuestas por segundo a 800
rps, contra 573,2 con 10 [E-305] [E-325]. A 600 rps, el p50 de `GET /rates` en
el servidor bajó de 131,1 a 5,2 ms [E-306] [E-326].

*TLS cifró el tráfico sin cambiar la latencia.* Hasta 400 rps, la mediana en
el cliente quedó a lo sumo 10,9 ms sobre la del caso escalado, dentro de la
variación de 15 ms de la latencia de base [E-304] [E-303].

*La red domina la latencia que ve el cliente.* Hasta 100 rps, `GET /rates`
tardó de 169 a 172,5 ms en el cliente, y la latencia de base es de 169 ms
[E-114] [E-90]. Desde 600 rps, el generador usó toda su CPU en todas las
ejecuciones [E-127] [E-152] [E-312] [E-332].

*Recomendación.* Desplegar 2 nodos con el tope de 5 conexiones por nodo y TLS.
Es la configuración que más respuestas atendió a 800 rps, contra 647,6 de 1 nodo
[E-325] [E-116]. Con este Postgres, más nodos no incrementan throughput, y cada
cambio de `vmss_instances` exige recalcular `db_pool_max` (sección 9.2).

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
  (
    caso: [Terminación TLS, base del tope de conexiones (10 por nodo)],
    nodos: 2,
    escenario: [rampa del TP 1 con pool (pool-ramp), por HTTPS],
    throughput: [600 rps; 573,2 respuestas/s a 800 rps],
    mediana: [262,5 a 478,3 ms],
    p95: [1.408 a 2.780 ms],
    errores: [sin timeouts; 9,8 % de 502 de ARCA],
    limitante: [Postgres, por CPU, con 16 esperas `Lock`],
    evidencia: "E-304",
  ),
  (
    caso: [Tope de conexiones (5 por nodo)],
    nodos: 2,
    escenario: [rampa del TP 1 con pool (pool-ramp), por HTTPS],
    throughput: [600 rps; 681,8 respuestas/s a 800 rps],
    mediana: [183,1 a 257,3 ms],
    p95: [983 a 1.408 ms],
    errores: [sin timeouts; 9,9 % de 502 de ARCA],
    limitante: [Postgres, por CPU, con el generador saturado desde 600 rps],
    evidencia: "E-324",
  ),
))
