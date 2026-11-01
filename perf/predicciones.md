# Predicciones

Hipótesis con predicción numérica de cada prueba de carga, como pide el
enunciado (README.md, *Predicción antes de medir*).

**Regla:** la predicción de un caso se commitea **antes** que sus resultados
(`perf/results/<caso>/`). El historial de commits es la prueba. Una predicción
no se edita después de medir: la comparación con el resultado y la explicación
de la diferencia van en el informe.

Cada entrada lleva:

- **Caso y escenario:** configuración (nodos, táctica) y escenario de Artillery.
- **Métrica y predicción:** al menos una métrica con un número. Por ejemplo,
  latencia mediana o p95, errores, uso de CPU de los nodos o de ARCA.
- **Razonamiento:** por qué ese número, a partir del código, la infraestructura
  y los resultados del TP 1.

Para el caso escalado, la predicción dice además si el throughput escala
proporcionalmente a la cantidad de nodos y, si no, qué componente lo impide.

## Latencia de base

<!-- Medición contra `/`, sin carga, antes de las pruebas. -->

## Caso 1 nodo

## Caso escalado

## Tácticas
