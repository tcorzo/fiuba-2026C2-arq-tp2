#import "../plantilla.typ": *

= Docker Compose local vs. nube

En el TP 1, Docker Compose corría todo el sistema en un equipo de cada
integrante. En Azure, cada componente corre en su propio recurso (sección 4).
Esta sección compara los dos despliegues y su impacto en cada atributo de
calidad. Cuando hay una medición de los dos lados, la citamos.

== Performance: recursos propios por componente

En el TP 1, todos los contenedores compartían la CPU de un equipo, con límites
de cgroup. Las tres réplicas de la `api` tenían 0,25 CPU cada una, y `db`, otras
0,25 [E-222] [E-129]. Artillery corría en el mismo equipo, fuera de esos
límites [E-225].

En Azure, el nodo tiene 1 CPU propia [E-205], y Postgres, un servidor
`Standard_B1ms` aparte [E-208]. ARCA tiene sus 0,5 CPU en Azure Container
Instances [E-210]. El generador de carga corre fuera de Azure [E-89].

Con más CPU para cada componente, la capacidad creció. La rampa final del TP 1
tuvo timeouts desde 200 rps [E-130]. Con un solo nodo, Azure sostuvo 600 rps
sin timeouts [E-114]. El límite pasó a ser la escritura de los exchanges en Postgres
(sección 7).

== Performance: la red entre el cliente y el servicio

En el TP 1, el request no salía del equipo. La mediana de `GET /rates` en el
cliente fue de 1 ms hasta 100 rps [E-130]. En Azure, el request cruza internet
desde Buenos Aires hasta `centralus`. Entre 10 y 100 rps, la mediana de
`GET /rates` en el cliente fue de 169 a 172,5 ms [E-114]. En el nodo, el p50 de
esa ruta fue de 1,1 a 1,5 ms [E-115].

Casi toda la latencia que ve el cliente es red: la latencia de base es de
169 ms [E-90]. Por eso, en Azure, una mejora de la latencia del servicio menor
que la variación de la base, 11 ms, no se ve desde el cliente (sección 2).

La red también limitó al generador. Con una conexión nueva por request, el
generador resolvió el nombre del load balancer 134 veces por segundo [E-86], y
desde 200 rps los requests terminaron en timeout sin llegar al nodo [E-84]
[E-85]. Con un pool de conexiones keep-alive, el problema desapareció [E-112].
En el TP 1, el generador y el servicio estaban en el mismo equipo y este límite
no existía.

== Escalabilidad

En el TP 1, las réplicas de la `api` dividían un presupuesto fijo de CPU: agregar
una réplica le quitaba CPU a las otras [E-222]. En Azure, escalar agrega una VM
con su propia CPU. El caso escalado cambió una variable de Terraform [E-136], y
los dos nodos tenían el mismo runtime [E-216].

El costo de escalar también cambió. En Docker Compose alcanzaba con cambiar la
cantidad de réplicas [E-222]. En Azure, después de aplicar Terraform, hay que correr el
setup y el deploy de Ansible en el nodo nuevo [E-230]. Postgres y ARCA no se
replican en ninguno de los dos despliegues, y en Azure el throughput escalado
quedó limitado por Postgres (sección 8).

== Disponibilidad

En el TP 1, el equipo era un único punto de falla para todo el sistema. Docker
reiniciaba la `api` si terminaba, y su healthcheck pedía `GET /rates` cada 5 s
[E-223]. En Azure, pm2 reinicia el proceso [E-18], y el load balancer prueba
cada nodo con un probe TCP [E-207]. Ese probe no detecta un proceso colgado con
el puerto abierto (sección 3).

Con dos nodos, el servicio deja de depender de una sola VM, aunque no probamos
la caída de un nodo. Postgres y ARCA siguen
siendo una sola instancia cada uno [E-200]. Postgres es administrado: Azure
guarda backups durante 7 días [E-04], y el volumen de Docker deja de existir.

== Seguridad

En el TP 1, la contraseña de Postgres estaba escrita en `docker-compose.yml`
[E-224], y los puertos se publicaban en el equipo, alcanzables desde su red
local [E-41]. En Azure, Terraform genera la contraseña [E-228], que no está en el
repositorio. Postgres no tiene acceso público [E-208], y el servicio se conecta
con `sslmode=verify-full` [E-65]. Los nodos no tienen IP pública [E-05].

El load balancer, en cambio, expone el servicio a internet, sin TLS [E-206]. En
el TP 1, nginx terminaba TLS [E-38]. En Azure, el tráfico del cliente cruza
internet en texto plano (sección 3).

== Observabilidad

En el TP 1, Graphite, Grafana y cAdvisor eran contenedores del mismo equipo, con
límites para no quitarle CPU al sistema bajo prueba [E-227].

En Azure, el agente de Datadog corre en cada nodo [E-07] y manda las métricas al
servicio de Datadog [E-76]. Postgres y ARCA son servicios administrados y no corren
el agente. Sus métricas salen de Azure Monitor: CPU de Postgres [E-121], CPU
de ARCA [E-124] y sesiones por tipo de espera [E-122]. Esta última métrica
exige un parámetro de Postgres que habilitamos con Terraform [E-229].

== Despliegue y reproducibilidad de las mediciones

En el TP 1, cada integrante midió en su máquina, y los valores absolutos de dos
máquinas no se podían comparar [E-226]. En Azure, todo el grupo mide contra los
mismos SKUs [E-204] [E-208] [E-210]. Las ejecuciones que comparamos corren desde
un solo generador de carga (sección 2).

`mise run up` aplica dos stacks de Terraform y corre Ansible a través del
jumpbox [E-230] [E-66]. Postgres se factura por hora, así que destruimos la
infraestructura al final de cada sesión, y `seed.js` recarga el estado inicial
[E-231].
