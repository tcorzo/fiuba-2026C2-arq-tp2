#import "../plantilla.typ": *

= Arquitectura desplegada

Las dos configuraciones medidas tienen los mismos componentes y conectores.
Sólo cambia la cantidad de nodos del VMSS: uno en el caso de 1 nodo y dos en el
caso escalado. Terraform fija esa cantidad en el VMSS [E-05].

== Componentes

#table(
  columns: (auto, 1fr, auto),
  inset: (x: 6pt, y: 4pt),
  stroke: 0.4pt + suave,
  align: (left, left, left),
  table.header([*Componente*], [*Qué es en Azure*], [*Evidencia*]),
  [Load balancer],
  [Load balancer Standard con IP pública. Trabaja en la capa 4: una regla TCP
    del puerto 80 al 3000 y un probe TCP al 3000],
  [\[E-05\]],

  [Nodo del VMSS],
  [VM `Standard_F1als_v7`, sin IP pública. Su NIC está en el backend pool del
    load balancer],
  [\[E-05\] \[E-60\]],

  [exchange-service], [pm2 arranca un proceso de Node en cada nodo], [\[E-61\]],

  [Transferencias],
  [La dependencia de transferencias simulada: una espera de 200 a 400 ms
    dentro del mismo proceso, no un servicio aparte],
  [\[E-63\]],

  [Agente de Datadog], [Ansible instala un agente en cada nodo], [\[E-07\]],

  [ARCA],
  [El contenedor `arqsoft/arca:1.0.0` en Azure Container Instances, con
    0,5 vCPU, 0,5 GiB e IP privada en el puerto 8080],
  [\[E-59\]],

  [Postgres],
  [Azure Database for PostgreSQL Flexible Server 18, `B_Standard_B1ms`, sin
    acceso público],
  [\[E-04\]],

  [Jumpbox],
  [VM con IP pública y SSH. Ansible llega a los nodos a través de ella],
  [\[E-64\] \[E-66\]],
)

El VMSS, el jumpbox, ARCA y Postgres tienen cada uno su subnet en la VNet
`10.0.0.0/16`. Las subnets
de ARCA y de Postgres están delegadas a sus servicios [E-58]. Sólo el load
balancer y el jumpbox tienen IP pública [E-05] [E-64].

== Conectores

#table(
  columns: (auto, auto, 1fr, auto),
  inset: (x: 6pt, y: 4pt),
  stroke: 0.4pt + suave,
  align: (left, left, left, left),
  table.header([*De*], [*A*], [*Protocolo y propiedades*], [*Evidencia*]),
  [Cliente],
  [Load balancer],
  [HTTP/1.1 al puerto 80, sin TLS, por internet],
  [\[E-05\] \[E-19\]],

  [Load balancer],
  [Nodo],
  [TCP al puerto 3000. El load balancer no lee HTTP],
  [\[E-05\]],

  [exchange-service],
  [ARCA],
  [HTTP `POST /validar`, con timeout de 2000 ms y sin reintentos],
  [\[E-49\] \[E-51\]],

  [exchange-service],
  [Postgres],
  [SQL sobre TLS (`sslmode=verify-full`) al puerto 5432, desde un pool de
    conexiones por proceso],
  [\[E-62\] \[E-65\]],

  [exchange-service],
  [Agente de Datadog],
  [UDP (DogStatsD) a `127.0.0.1:8125`, sin salir del nodo. Un paquete perdido
    no genera error en el servicio],
  [\[E-74\] \[E-75\]],

  [Agente de Datadog],
  [Datadog],
  [HTTPS por internet, al site de Datadog que fija `DATADOG_SITE`],
  [\[E-76\]],

  [Operador],
  [Jumpbox y nodos],
  [SSH desde internet al jumpbox, y del jumpbox a
    los nodos: Ansible y pm2],
  [\[E-58\] \[E-66\]],
)

== Caso de 1 nodo

#figure(
  image("../../diagramas/arquitectura-1-nodo.svg", width: 100%),
  caption: [Componentes y conectores del caso de 1 nodo.],
) <cc-1-nodo>

== Caso escalado

#figure(
  image("../../diagramas/arquitectura-escalado.svg", width: 100%),
  caption: [Componentes y conectores del caso escalado. En verde, lo que se
    replica.],
) <cc-escalado>

Al escalar se replica el nodo completo: el proceso, su pool de conexiones y su
agente. El load balancer reparte las conexiones entre los dos nodos [E-05].
Postgres y ARCA no se replican: los dos nodos usan el mismo servidor y el mismo
contenedor [E-04] [E-59].

#pendiente[
  La evidencia de que cada configuración estuvo desplegada así: la salida de
  `terraform state list`, `terraform output` y `az vmss list-instances` de cada
  caso. La del caso de 1 nodo está en `evidencia/1-node/`, en la rama
  `case/1-node`; se cita cuando esa rama llegue a `main`. La del caso escalado
  se toma cuando se despliegue.

  La configuración de la táctica superadora, si cambia algún componente o
  conector.
]
