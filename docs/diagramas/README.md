# Diagramas

Fuentes PlantUML de los diagramas C&C del informe, uno por configuración
medida (1 nodo, escalado y cada táctica), con Redis y ARCA.

`mise run diagrams` renderiza cada `.puml` a `.svg` (para el informe) y `.png`.
Los renders se commitean: el layout de PlantUML depende de la versión local de
Graphviz, así que no son reproducibles. Después de editar un `.puml`, renderizar
y mirar el PNG antes de commitear. Nunca editar un `.svg` a mano.
