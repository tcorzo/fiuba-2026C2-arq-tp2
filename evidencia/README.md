# Evidencia

Salidas citadas en el informe como `[E-NN]` que no son reportes de Artillery
(esos van en `perf/results/<caso>/`). Una carpeta por configuración medida:

```
evidencia/
  1-nodo/      terraform-state-list.txt, terraform-output.txt, vmss-instances.txt, ...
  escalado/
  <táctica>/
  arca/        extractos del log con validaciones aprobadas y rechazadas
```

Para cada configuración medida va la evidencia de que estaba desplegada así:
la salida de `terraform state list` y `terraform output` de cada stack, y la de
`az vmss list-instances` (solo columnas que no identifiquen la suscripción). Se
toma con la infraestructura de ese caso levantada, en la misma sesión que la
prueba de carga.

Cada archivo se declara en `docs/informe/evidencia.yml` con su ID.

**Antes de commitear, leer cada archivo.** No puede tener secretos: API keys,
claves privadas, `terraform.tfvars`, `terraform.tfstate`. El repositorio es
público. Una key commiteada se revoca y se reemplaza, no alcanza con borrarla.
El hook `gitleaks` y el job `secrets` de CI ayudan, pero no reemplazan la
lectura.

Los archivos van como los escribió el comando que los generó. No se editan a
mano: la evidencia adulterada es falta grave.
