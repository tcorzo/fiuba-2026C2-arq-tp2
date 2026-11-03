# Punto de partida para el TP 2 de Arquitectura de Software (75.73/TB034) del 2do cuatrimestre de 2026

> La fecha de entrega para el informe y el código será el __*jueves 19/11 a las 17:59hs*__.

El informe debe entregarse en formato PDF dentro del repositorio, y debe respetar el límite de extensión, la estructura y las reglas de evidencia indicadas en las secciones [Informe](#informe), [Evidencia](#evidencia) y [Uso de herramientas de IA](#uso-de-herramientas-de-ia).

## Contexto

Para este Trabajo, migraremos el servicio de cambio de monedas de arVault a la nube, desplegado sobre Azure. Tomaremos como base la implementación del TP 1 con las modificaciones que realizaron ustedes (las que hayan funcionado mejor según las pruebas que hicieron).

En cada caso, deberán analizar y explicar qué está ocurriendo según lo que visualizan. Si encuentran algún cuello de botella o limitación, deben proponer y probar alguna táctica superadora, siempre que tenga sentido dentro del caso analizado. Discutan las diferencias entre tener la aplicación orquestada con Docker Compose en un equipo local y desplegada en la nube.

Además de los casos obligatorios (1 nodo y escalado, con storage externo y la integración con ARCA, explicada más abajo), deben implementar __una o dos tácticas superadoras__, elegidas a partir de los cuellos de botella o limitaciones que hayan observado con evidencia. Tácticas adicionales no suman nota y no serán leídas. Se evalúa la profundidad del análisis, no la cantidad de tácticas.

Todo cambio de infraestructura debe hacerse mediante los archivos de Terraform y Ansible del repositorio. Los cambios hechos a mano en el portal de Azure o por SSH no se consideran implementados, porque no son reproducibles.

Tanto para escalar horizontalmente como para agregar una instancia del storage, cada grupo deberá modificar/agregar archivos de Terraform como sea necesario.

### Storage

Para este TP, el storage deberá implementarse en Redis o en algún otro motor de base de datos que Azure soporte en el modelo *platform as a service*. Si lo hicieron de manera opcional en el TP 1, la implementación es similar, solo cambian los datos de conexión.

Para crear una instancia de Redis en Azure, mirar el [recurso azurerm_managed_redis de Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/managed_redis). Les recomendamos mirar los archivos de Terraform que les damos para ver cómo pueden utilizar un archivo de configuración que se modifique dinámicamente al crearse la infraestructura y tener disponible los datos de conexión al storage.

### Consulta a API externa

Simularemos la existencia de una API externa de ARCA mediante el despliegue de un contenedor Docker (basado en una imagen provista por la cátedra) en el servicio correspondiente de Azure.

Para poder interactuar con esta API, deberán agregar al body del request que recibe el servicio de ustedes un campo "dni", de tipo texto, que recibirá el número de DNI del cliente que quiere realizar el cambio de monedas. Este número deberá ser enviado por el generador de carga. Los números válidos de DNI irán de 1000000 a 99999999.

La API de ARCA provee un único endpoint, `/validar`, que recibe mediante POST un JSON como el que sigue:

```json
  {
    "dni": "40101235"
  }
```

El servicio validará que el número de DNI no tenga restricciones fiscales para ejecutar operaciones de compra-venta de moneda extranjera, y devolverá el resultado de la validación, junto con un código de autorización (solo si no hay restricciones). Ejemplo:

```json
  {
    "ok": true,
    "codigoAutorizacion": "434351b7-952a-4a6c-9197-6759477b528c"
  }
```

El resultado debe registrarse en el log junto con el código de autorización (de haber sido aprobado), además de devolver una respuesta apropiada al cliente.

Se les recomienda generar métricas propias sobre el comportamiento de este servicio para correlacionarlo con el comportamiento del servicio de arVault.

Junto con el enunciado les damos una aplicación de ejemplo, para que vean cómo invocar al servicio y, además, puedan verificar la primera vez que levantan la infraestructura que todo funciona. El servicio de ARCA escuchará en la URI que se configura automáticamente en `node/config.js`. Vean el archivo `arca.tf`.

Una vez que hayan visto el uso en la aplicación de ejemplo, pueden reemplazarla por el código de ustedes. Traten de aprovechar el mecanismo de actualización de la configuración que les damos.

### Escalamiento

Probarán el funcionamiento del servicio inicialmente con 1 nodo y escalando luego a 2. Para escalar en un Virtual Machine Scaling Set (VMSS), deben ajustar el parámetro *instances* según lo deseado.

Para la administración de las instancias del VMSS se utilizará un jumpbox.

## Informe

### Punto de partida desde el TP 1

El informe debe indicar qué tácticas del TP 1 trasladaron a la nube y cuáles no, y por qué, citando la evidencia del TP 1 que justifica cada decisión. Tengan en cuenta que en este despliegue no hay nginx. El reverse proxy/load balancer de Azure ocupa su lugar en el camino del request. Las tácticas que dependían de nginx deben reconsiderarse explícitamente.

### Predicción antes de medir

Antes de ejecutar cada prueba de carga (1 nodo, caso escalado y cada táctica), el grupo debe registrar una __hipótesis con una predicción numérica__ sobre al menos una métrica (por ejemplo, latencia mediana o p95, errores, uso de CPU de los nodos o de ARCA) y el razonamiento que la sustenta, basado en el código, la infraestructura y los resultados del TP 1. Luego de medir, deben comparar el resultado con la predicción y explicar la diferencia.

En particular, para el caso escalado deben predecir __antes de medir__ si el throughput escalará proporcionalmente a la cantidad de nodos y, si no, qué componente lo impedirá.

No se penaliza errar la predicción. Se evalúa la calidad del razonamiento y de la explicación de la discrepancia. Las predicciones deben estar commiteadas en el repositorio (por ejemplo, en un archivo `perf/predicciones.md` o similar) __antes__ que los resultados de la prueba correspondiente. El historial de commits debe permitir verificarlo. Referencien en el informe cuál es el archivo que tiene las predicciones.

### Decisiones descartadas

Incluir al menos dos alternativas (tácticas, servicios de Azure, tecnologías o configuraciones) que el grupo consideró y __no__ implementó, explicando por qué fueron descartadas en el contexto de este sistema. Un párrafo por alternativa.

### Formato y extensión

El informe tiene un __límite de 30 páginas__ (A4, fuente de tamaño 11, márgenes de 2,5 cm.), incluyendo diagramas y screenshots. La carátula, el índice general y el índice de evidencia no cuentan para el límite.

__Lo que exceda el límite no será leído__, y cualquier conclusión que dependa de contenido no leído se considerará no fundamentada. Pueden incluir anexos (en el repositorio o al final del PDF), pero los anexos _no se evalúan_. Todo lo que quieran que se califique debe estar en el cuerpo del informe.

El informe debe seguir esta estructura. Las extensiones indicadas son orientativas, pero el límite total es estricto.

|  | Sección | Extensión orientativa |
|---|---------|-----------------------|
| 1 | Resumen ejecutivo: hallazgos principales, recomendación y __tabla de resultados clave__ (ver abajo) | 1 página |
| 2 | Entorno: región, ubicación del generador de carga, tipo de conexión a internet del generador de carga, ancho de banda disponible, latencia de red de base | 1 página |
| 3 | Punto de partida desde el TP 1 | 2 páginas |
| 4 | Arquitectura desplegada: diagrama C&C para cada configuración, incluyendo Redis y ARCA | 4 páginas |
| 5 | Docker Compose local vs. nube. Diferencias y su impacto en los QA | 2 páginas |
| 6 | Integración con ARCA: implementación, manejo de errores y métricas propias | 2 páginas |
| 7 | Caso 1 nodo: escenarios, predicciones, resultados | 4 páginas |
| 8 | Caso escalado: escenarios, predicciones, resultados, cuello de botella identificado (si aparece alguno) | 4 páginas |
| 9 | Tácticas superadoras (una subsección por táctica: problema observado, QA objetivo, predicción, implementación, resultados, tradeoffs) | 3 páginas por táctica |
| 10 | Decisiones descartadas | 1 página |
| 11 | Conclusiones | 1 página |
| 12 | Uso de herramientas de IA | 1 página |
| — | Índice de evidencia | no cuenta para el límite |

La __tabla de resultados clave__ del resumen ejecutivo debe tener una fila por caso medido (1 nodo, escalado y cada táctica) con: cantidad de nodos, escenario de carga, throughput sostenido, latencia mediana y p95, tasa de errores, componente que limita el rendimiento, y el identificador de evidencia correspondiente. Es la referencia que se usará en la defensa del TP en el examen final.

### Latencia de red de base

Las pruebas de carga se ejecutan desde fuera de Azure, por lo que toda latencia medida incluye el tiempo de ida y vuelta por internet. Antes de las pruebas, deben medir la latencia de base contra el endpoint `/` (sin carga y sin pasar por ARCA ni Redis), informar desde dónde corrieron el generador de carga, y usar esa medición al interpretar los resultados. Todas las pruebas que se comparen entre sí deben ejecutarse desde la misma ubicación.

## Evidencia

__Toda__ afirmación relevante del informe (sobre el código, la infraestructura, el comportamiento del sistema o el impacto de una táctica) debe citar al menos un identificador de evidencia con el formato `[E-NN]`. Al final del informe debe incluirse un __índice de evidencia__: una tabla que, para cada identificador, indique qué es y dónde encontrarlo en el repositorio.

Ejemplo:

| ID | Descripción | Ubicación en el repositorio |
|----|-------------|-----------------------------|
| E-01 | Reporte de Artillery, 1 nodo, escenario `exchange-ramp` | `perf/results/1-nodo/exchange-ramp.json` |
| E-02 | Screenshot del dashboard de Datadog, 1 nodo, escenario `exchange-ramp` | `perf/results/1-nodo/exchange-ramp.png` |
| E-03 | Salida de `terraform state list` del caso escalado | `evidencia/escalado/terraform-state-list.txt` |
| E-04 | Fragmento de código que muestra … | `node/app.js`, líneas 40–55 |

La infraestructura se destruye al terminar el TP, por lo que la evidencia debe quedar __en el repositorio__. No se aceptan links a dashboards de Datadog ni a recursos de Azure como única evidencia. Requisitos:

- Los __reportes crudos__ de cada prueba de carga (por ejemplo, la salida de `artillery run --output <archivo>.json`) deben estar commiteados en el repositorio, junto al escenario que los generó.
- Los __screenshots__ de Datadog deben mostrar el rango temporal de la prueba y ser consistentes con el reporte crudo correspondiente. Deben exportar también el JSON de los dashboards que usaron.
- Para cada configuración de infraestructura medida, debe haber evidencia de que estaba desplegada así: por ejemplo, la salida de `terraform state list`, `terraform output` o `az vmss list-instances`, y los cambios de Terraform/Ansible correspondientes en el historial de commits.
- La integración con ARCA debe evidenciarse con un extracto del log de la aplicación que muestre validaciones aprobadas (con su código de autorización) y rechazadas.
- Las observaciones sobre el código deben tener una ejecución reproducible (request y response) que demuestre el comportamiento.
- La evidencia __no debe contener secretos__ (API keys, claves privadas, `terraform.tfvars`, `terraform.tfstate`). Revisen salidas y screenshots antes de commitearlos.
- Una afirmación sin identificador de evidencia se considera no fundamentada.

### Verificación

La corrección incluye una __verificación por muestreo__: se eligen al azar afirmaciones del informe y se contrastan contra su evidencia en el repositorio y contra el comportamiento esperable del sistema. __Si una afirmación verificada no está respaldada por la evidencia que cita, o la evidencia es inconsistente con el repositorio, se considera no fundamentada toda la sección que la contiene.__ La evidencia fabricada o adulterada se considera falta grave.

## Uso de herramientas de IA

Pueden usar agentes y herramientas de IA. __El uso de IA, por sí mismo, no penaliza ni resta nota__. Lo que se evalúa es que el grupo entienda, verifique y pueda defender todo lo entregado.

La sección "Uso de herramientas de IA" del informe debe incluir:

1. Qué herramientas usaron y para qué partes del trabajo (código, Terraform, Ansible, escenarios de carga, redacción, análisis, etc.).
2. __Al menos un caso concreto__ en el que la herramienta propuso algo incorrecto, incompleto, desactualizado o inadecuado para este sistema. Por ejemplo, recursos o atributos de Terraform inexistentes u obsoletos, configuraciones inseguras, conclusiones que no se correspondían con las métricas. Indicar qué propuso, cómo lo detectaron (idealmente con evidencia `[E-NN]`) y qué hicieron en su lugar.

Recuerden que la responsabilidad sobre cada afirmación, cada línea de código y cada recurso desplegado es __del grupo__, independientemente de cómo se haya producido.

## Defensa del TP en el examen final

En el examen final, cualquier docente de la materia puede pedirles que expliquen aspectos de los TPs __de su propio grupo__, con el informe a la vista: un número de la tabla de resultados clave, el cuello de botella identificado, una táctica y su tradeoff, una decisión descartada o un fragmento del código o la infraestructura entregados. Las preguntas no requieren que quien examina conozca el TP en detalle. Requieren que ustedes lo conozcan.

Cada integrante es responsable de entender la totalidad del trabajo entregado por su grupo, no solo la parte que realizó.

## Condiciones sobre la entrega

1. El trabajo debe entregarse __completo__. No se aceptan entregas parciales.
2. __Toda__ afirmación que se realice debe estar apoyada en __evidencia__, citada según la sección [Evidencia](#evidencia). Si se encuentra alguna afirmación que no está correctamente fundamentada con evidencia, se disminuirá la nota.
3. Asumimos que todo el grupo participa en la resolución del trabajo. De ocurrir problemas o surgir contratiempos, es el grupo quien debe responder y solucionarlos. Pueden consultar a los docentes pero deben demostrar primero que intentaron solucionarlos internamente.
4. El uso de herramientas de IA está permitido y debe documentarse según la sección [Uso de herramientas de IA](#uso-de-herramientas-de-ia). La evidencia fabricada, adulterada o inconsistente con el repositorio se considera __falta grave__.
5. El informe debe respetar el límite de extensión y la estructura indicados en [Formato y extensión](#formato-y-extensión).
6. De haber defectos importantes en el desarrollo o en el informe del TP, se solicitará una re-entrega. Esto tiene un impacto considerable en la nota final. No se considera a un TP hecho parcialmente como un caso de re-entrega. Tampoco se aceptan entregas con secciones sin desarrollar o con contenido de relleno.

## Setup

### Archivo de variables

- Crear un archivo `terraform.tfvars` en cada stack de Terraform (`infra/envs/prd/foundation/` e `infra/envs/prd/platform/`), copiando el `terraform.tfvars.example` que hay en cada uno. Ver [`infra/envs/prd/README.md`](infra/envs/prd/README.md).

    > __ATENCIÓN: EVITEN COMMITEAR ESTE ARCHIVO AL REPOSITORIO. LAS API KEYS EN GENERAL NO DEBEN COMMITEARSE. DE HACERLO DEBEN ELIMINARLAS Y CREAR NUEVAS__
    _

### Docker Hub

- Crear una cuenta gratuita en [Docker Hub](https://hub.docker.com/)
- Ir a `<Usuario> -> Personal access tokens` y crear un token de acceso con permiso *Repo Public Read-only*
- Agregar la información a `infra/envs/prd/foundation/terraform.tfvars`:

```properties
dockerhub_username="<Nombre de usuario>"
dockerhub_token="<Token>"
```

### Azure

- Crear una cuenta en [Azure](https://azure.microsoft.com/).
- Desde SSH Keys, generar un par de claves (key/secret). Dejar la clave privada en el directorio raíz del TP (o referenciarla con un link simbólico). Llamarla `key.pem`. Tomar nota del nombre que se le asignó al par de claves.
- Instalar [`Azure CLI`](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Ejecutar `az login` e iniciar sesión en Azure. Pegar la __subscription ID__ (que se muestra luego del login exitoso) en una variable llamada __azure_sid__ en el `terraform.tfvars` de ambos stacks, debe quedar de esta manera:

```properties
azure_sid = "<Subscription ID de Azure>"
```

### Datadog

- Crear una cuenta con el [pack estudiantil de GitHub](https://education.github.com/pack) en [Datadog](https://www.datadoghq.com/)
- Ir a `<Usuario> -> Organization Settings -> API Keys` y obtener la API Key. Tiene que ser una __API key__ (32 caracteres hexadecimales), no una Application Key (empieza con `ddapp_`).
- Verificar el host en la URL del navegador y sacarle el prefijo "app.": ese es el __site__ de la cuenta. Por ejemplo, __app.datadoghq.com__ es `datadoghq.com` y __us5.datadoghq.com__ es `us5.datadoghq.com`.
- Guardar ambos valores en las variables de entorno `DATADOG_API_KEY` y `DATADOG_SITE`, en el `mise.local.toml` de la raíz del repositorio (está en el `.gitignore`), debe quedar de esta manera:

```toml
[env]
DATADOG_API_KEY = "<API key de Datadog>"
DATADOG_SITE = "<site de Datadog>"
```

`DATADOG_SITE` no tiene valor por defecto: una key enviada al site equivocado pierde los datos sin mostrar ningún error. Por eso `mise run up`, `mise run ansible:setup` y `mise run perf:run` se detienen si falta alguna de las dos variables. Más detalles en [`infra_setup.md`](infra_setup.md).

### Terraform

- Instalar las herramientas con [mise](https://mise.jdx.dev/): `mise install` instala Terraform, Azure CLI, Ansible y Node en las versiones fijadas en `mise.toml`. `mise tasks` lista las tareas disponibles.
- Revisar los archivos `variables.tf` de cada stack en `infra/envs/prd/` y actualizar los valores default de las variables que corresponda. Este archivo sí será commiteado, así que solo poner aquí valores default que puedan exponerse (para los demás, deben estar las variables declaradas aquí pero los valores deben estar en `terraform.tfvars`, que nunca hay que commitearlo)
  - Para "location" (region), recomendamos utilizar "eastus2" o "westus2".
  - Verificar que el nombre del par de claves creado en Azure coincida con el de la variable "ssh_key_name" y que su resource group coincida con "ssh_key_group_name".
- Ejecutar `mise run infra:init foundation` y `mise run infra:init platform`. Esto inicializa la configuración que requiere terraform, e instala los providers necesarios.

### Ansible

- Ansible se instala con `mise install`.
- La colección de Datadog para Ansible (`ansible/requirements.yml`) se instala sola al ejecutar `mise run ansible:setup`.
- `ansible/vmss_setup.yml` toma el site de Datadog de la variable de entorno `DATADOG_SITE`.

## Correr los servidores

La tarea `mise run up` crea la infraestructura y corre los servidores correspondientes.

```bash
# Seteo los permisos apropiados para que la key sea válida
chmod 400 key.pem

# Inicia sesión en Azure, aplica los stacks foundation y platform, instala el software en el VMSS y despliega la app
mise run up
```

Terraform crea, en el directorio de cada stack, un archivo local llamado `terraform.tfstate` que tiene el resultado de la aplicación del plan. Usa ese archivo luego para detectar diferencias y definir un nuevo plan si hay modificaciones a la infraestructura. Ese archivo __no debe perderse__, pero como [puede contener información sensible en texto plano](https://www.terraform.io/docs/state/sensitive-data.html) no es recomendable commitearlo sin tomar algunas precauciones. Además, si se destruye y regenera la infraestructura, cambiará mucho, con lo que es muy propenso a conflictos en git.

La recomendación, por lo tanto, es que cada cual tenga su propia cuenta de Azure y de Datadog, y mantenga su propio `terraform.tfstate` en su computadora sin necesidad de compartirlo. [Acá](https://www.terraform.io/docs/state/remote.html) tienen más información e instrucciones sobre qué hacer si quieren operar todos los integrantes del grupo sobre una misma cuenta de Azure y compartir su tfstate.

### Verificación de funcionamiento

Una vez levantados los servidores, se puede verificar su correcto funcionamiento enviando un request a la URL del load balancer. `infra/output.sh` la lee del output `lb_fqdn` del stack `platform`:

```sh
curl "http://$(infra/output.sh platform lb_fqdn)/"
```

En el primer deploy, la tarea `Stop old version` falla con `Process or Namespace server.js not found` y Ansible muestra `...ignoring`: todavía no hay ningún proceso para detener. El deploy está bien si el resumen final muestra `failed=0`.

Con esto pueden verificar que la aplicación Node de ejemplo levantó correctamente.

### Cambio de cantidad de instancias en el VMSS de la aplicación Node

Al cambiar la cantidad de instancias en el VMSS, una vez aplicados los cambios en la infraestructura, pueden ejecutar:

```sh
mise run ansible:setup
mise run app:deploy
```

Estos scripts actualizan el inventario con las direcciones IP de los nodos del VMSS y luego instalan la aplicación Node en cada uno. Puede ejecutarse todas las veces que sea necesario (si hay nodos que ya tienen las herramientas necesarias, para éstos la ejecución será más rápida).

### Re-deploy de la aplicación Node por modificaciones en el código

Si sólo se modificó la app Node y se la quiere actualizar (sin haber cambiado la cantidad de instancias), pueden ejecutar el deploy únicamente:

```sh
mise run app:deploy
```

### Administración de la aplicación Node

El proyecto usa [pm2](https://pm2.keymetrics.io/) para daemonizar y administrar la aplicación Node. Pueden ver [aquí](https://pm2.keymetrics.io/docs/usage/quick-start/) la documentación para acceder a los logs, detener y arrancar la aplicación, etc.

Si necesitan ingresar a alguna instancia de VMSS para ver logs o administrarla en general, deben ejecutar el siguiente comando desde la raíz del repositorio (reemplazando en el lugar apropiado por la IP interna de la instancia):

```sh
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -o StrictHostKeyChecking=no -W %h:%p -q azureuser@$(infra/output.sh foundation jumpbox_fqdn) -i ./key.pem" -i ./key.pem azureuser@<IP privada del host>
```

Esto usa al jumpbox de proxy SSH para evitar exponer con una IP pública a los nodos del VMSS. Utilizamos el mismo par de claves para el jumpbox y los nodos por simplicidad. Normalmente se usan pares distintos.

### Envío de métricas a Datadog

El agente de Datadog se instala en cada instancia de Node automáticamente, cuando ejecutan `mise run ansible:setup` (`mise run up` lo invoca cuando crean la infraestructura).

Para enviar sus propias métricas, vean cómo hacerlo [aquí](https://docs.datadoghq.com/integrations/node/). Es muy sencillo porque el agente de Datadog abre el puerto de statsd en localhost y se encarga de enviar las métricas custom que recibe.

Para enviar métricas desde Artillery, vean la configuración [aquí](https://artillery.io/docs/guides/plugins/plugin-publish-metrics.html).

Antes de invocar a Artillery, ya sea utilizando `mise run perf:run <escenario> <reporte>` (que llama a `perf/run.sh`; instalar Artillery antes con `mise run perf:install`) o de manera directa, tienen que estar definidas las variables de entorno `DATADOG_API_KEY` y `DATADOG_SITE` (ver la sección [Datadog](#datadog)). Si no usan `mise.local.toml`, pueden exportarlas en la terminal:

```sh
export DATADOG_API_KEY=<API key de Datadog>
export DATADOG_SITE=<site de Datadog>
```

Esta es una manera con la que evitan subir la key al repositorio. Pueden usar cualquier otro mecanismo que prefieran, mientras eviten commitearla.

Recuerden guardar el reporte crudo de cada ejecución en `perf/results/`, por ejemplo agregando `--output` a la invocación de Artillery (ver la sección [Evidencia](#evidencia)). El script `perf/run.sh` ya tiene la generación del reporte, revisen para ver cómo funciona.

El plugin de Datadog de Artillery toma el site de `DATADOG_SITE`, así que no hace falta configurar `apiHost` en los YAML de `perf/`.

## Destruir la infraestructura

Cuando hayan terminado con el TP, pueden destruir la infraestructura con `mise run down` (destruye `platform` y luego `foundation`). El par de claves que crearon a través de la UI de Azure deben eliminarlo también desde la UI.

## Cheatsheet de Terraform

```sh
# Ver lista de comandos
terraform help

# Ver ayuda de un comando específico, como por ejemplo qué parámetros/opciones acepta
terraform <COMMAND> --help

# Ver la versión de terraform instalada
terraform version

# Inicializar terraform en el directorio. Esto instala los providers e inicializa archivos de terraform
terraform init

# Ver el plan de ejecución pero sin realizar ninguna acción sobre la infraestructura (no lo aplica)
terraform plan

# Aplicar los cambios de infraestructura. Requiere aprobación manual, a menos que se especifique la opción `-auto-approve`
terraform apply

# Destruir toda la infraestructura. Requiere aprobación manual, a menos que se especifique la opción `-auto-approve`
terraform destroy

# Verifica que la sintaxis y la semántica de los archivos sea válida
terraform validate

# Lista los providers instalados.
terraform providers
```