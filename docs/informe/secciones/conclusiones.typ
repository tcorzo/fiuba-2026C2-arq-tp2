#import "../plantilla.typ": *

= Conclusiones

== Escalar lo que no limita empeora el sistema

El VMSS escala los nodos, pero el límite estuvo siempre en Postgres. Cada nodo
nuevo agrega un pool de 10 conexiones [E-62], y con él más transacciones sobre
las mismas dos filas de `accounts`. Con 2 nodos, Postgres gastó más CPU por
respuesta y completó un escalón menos [E-145] [E-138].

El throughput depende de cuántas transacciones concurrentes recibe Postgres, no
de cuántos nodos hay. El tope de conexiones lo confirma: con las mismas 10
transacciones que 1 nodo, las esperas `Lock` bajaron de 16 a 6 [E-308] [E-328].
Mientras cada exchange aprobado escriba las mismas dos filas, ni nodos ni
conexiones suben el techo. La mejora siguiente está en Postgres: más vCores, o
un modelo de datos que no concentre los exchanges en dos filas. No medimos
ninguna de las dos.

== La nube cambia qué se puede medir

En el TP 1, el generador y el servicio compartían equipo, y la mediana de
`GET /rates` era de 1 ms [E-130]. En Azure, la latencia de base es de 169 ms
[E-90], y una mejora del servicio menor que su variación no se ve desde el
cliente. Por eso comparamos las tácticas con métricas del servidor: el p50 por
ruta de Datadog y la CPU de Postgres de Azure Monitor.

El generador también limita: desde 600 rps usó toda su CPU [E-312] [E-332].
Por arriba de ese escalón, la latencia en el cliente incluye la espera en el
generador. Varios generadores, o uno más cerca de `centralus`, separarían los
dos límites.

== Lo que nos enseñaron las predicciones

En el caso escalado erramos la CPU de Postgres (C6). Supusimos que Postgres
hace el mismo trabajo por request con 10 o con 20 conexiones [E-145]. Ese
error eligió la segunda táctica: el tope de conexiones convirtió el supuesto en
hipótesis y la midió.

TLS mostró el riesgo contrario. T4 a T6 fallaron por un nodo que gastó casi el
doble de CPU por request que el otro, con el mismo código [E-311]. Sin la CPU
de cada proceso, no podemos atribuirle esa diferencia a TLS (sección 9.1).

== Riesgos que quedan

- Rate Limiting y Limit Exposure, aceptados sin componente que los ejecute
  (sección 3).
- El probe del load balancer es TCP: no detecta un proceso colgado con el
  puerto abierto (sección 3).
- No probamos la caída de un nodo. Con el tope, el nodo que queda atiende con
  5 conexiones (sección 9.2).
- El certificado es autofirmado: cifra el canal, pero no autentica al servidor
  (sección 9.1).
- El password de Postgres está en texto plano en el state de HCP Terraform y
  en la configuración de cada nodo. `terraform output` lo oculta [E-202],
  pero quien lea el state o entre a un nodo lo obtiene
  (#codigo("infra/modules/database/outputs.tf", "1-7", en: "4444086")).
