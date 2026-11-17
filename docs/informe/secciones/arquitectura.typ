#import "../plantilla.typ": *

= Arquitectura desplegada

Las dos configuraciones medidas tienen los mismos componentes y conectores.
Sólo cambia la cantidad de nodos del VMSS: uno en el caso de 1 nodo y dos en el
caso escalado. Terraform fija esa cantidad con la variable `vmss_instances`
[E-136].

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

== Lo que estaba desplegado en cada ejecución

Capturamos cada configuración el 15 de noviembre, mientras estaba levantada. La @tabla-desplegado compara las dos capturas.

#figure(
  {
    set par(justify: false)
    table(
      columns: (auto, 1fr, 1fr),
      inset: (x: 6pt, y: 4pt),
      stroke: 0.4pt + suave,
      align: (left, left, left),
      table.header([*Componente*], [*Caso 1 nodo*], [*Caso escalado*]),
      [Terraform],
      [`foundation`: 24 entradas en el state; `platform`: 8 [E-200] [E-201]. Las
        salidas, sin secretos [E-202] [E-203]],
      [Las mismas entradas y salidas [E-211] [E-212] [E-213] [E-214]],

      [VMSS],
      [Capacidad 1, `Standard_F1als_v7` [E-204]. Una instancia [E-111]],
      [Capacidad 2 [E-215]. Dos instancias con el último modelo [E-137]],

      [Nodo],
      [1 CPU, 1.893 MiB, Node v24.22.3 y pm2 7.1.2 [E-205]],
      [Lo mismo en cada nodo [E-216]],

      [Load balancer],
      [Regla TCP 80 → 3000 y probe TCP al 3000 cada 15 s [E-206] [E-207]],
      [Igual [E-217] [E-218]],

      [Postgres],
      [18, `Standard_B1ms` Burstable, 32 GB, sin acceso público,
        `max_connections` 50 [E-208] [E-209]],
      [Igual [E-219] [E-220]],

      [ARCA],
      [`arqsoft/arca:1.0.0`, 0,5 CPU, 0,5 GB, IP privada en el 8080 [E-210]],
      [Igual [E-221]],
    )
  },
  caption: [Estado de cada configuración desplegada, según `terraform` y
    `az`.],
) <tabla-desplegado>

Los dos states tienen las mismas entradas: el VMSS es un solo recurso, y la
cantidad de instancias es un atributo suyo. El caso escalado cambió sólo la
variable `vmss_instances` [E-136]. Después, Ansible instaló y desplegó el
servicio en el nodo nuevo, con el mismo runtime [E-216].

== Tácticas superadoras

#figure(
  image("../../diagramas/arquitectura-tls.svg", width: 100%),
  caption: [Componentes y conectores de la terminación TLS, sobre el caso
    escalado.],
) <cc-tls>

La terminación TLS cambia dos conectores y ningún componente. El cliente llega
en HTTPS al 443, y el load balancer reenvía TCP al 3443 de cada nodo, donde
Node termina TLS [E-155] [E-157]. El 80 pasa al 3080, que sólo responde `308`
hacia HTTPS [E-158]. El probe mira el 3443 [E-156].

El tope de conexiones no cambia la arquitectura: cada nodo abre un pool de 5
conexiones a Postgres en lugar de 10 [E-301] [E-321].
