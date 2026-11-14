#import "../plantilla.typ": *

= Decisiones descartadas

== Desplegar en `eastus2`, la región recomendada <descartada-region>

La cátedra recomienda `eastus2` o `westus2`. Nuestra suscripción no puede crear
PostgreSQL Flexible Server en ninguna de las dos. `list-skus` responde que la
suscripción tiene restringido el aprovisionamiento en esas regiones [E-10]
[E-11]. Una creación real en `eastus2` falló con "The location is restricted
from performing this operation" [E-12]. El servidor no tiene acceso público.
Los nodos lo alcanzan por una subnet delegada de la VNet [E-04], así que
Postgres tiene que estar en la región de la VNet. Movimos todo el despliegue a
`centralus`. Ahí `list-skus` no informa restricciones y la creación funcionó
[E-13] [E-14].

== Azure Managed Redis en lugar de Postgres

La cátedra sugiere Redis como storage. Lo descartamos y elegimos PostgreSQL
Flexible Server, también un servicio PaaS. El servicio del TP 1 ya corría
sobre Postgres, y su consistencia depende de transacciones. El puerto
`Atomically` exige que las escrituras de una operación se confirmen juntas o
ninguna [E-15]. El adaptador de Postgres lo cumple con `BEGIN` y `COMMIT`
[E-16]. Un adaptador de Redis tendría que reproducir esa garantía con `WATCH` o
con scripts Lua, y volver a verificar la reserva atómica de fondos (H-06). Ese
trabajo no resuelve ningún cuello de botella observado. Con el mismo motor, las
mediciones en Azure se comparan contra las del TP 1 sin cambiar dos variables a
la vez.
