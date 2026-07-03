# Proyecto Terraform — Balanceo de Tráfico en GCP

Infraestructura como código que despliega un balanceador HTTP global en Google
Cloud Platform con dos servicios independientes. El tráfico se distribuye entre
ambos servicios modificando únicamente dos variables en `terraform.tfvars`.

---

## Requisitos previos

- Terraform >= 1.6.0
- Google Cloud SDK (`gcloud`) autenticado:

```bash
gcloud auth application-default login
```

- Acceso IAM con rol **Editor** sobre el proyecto GCP indicado en `terraform.tfvars`.

---

## Despliegue inicial

```bash
terraform init
terraform apply
```

Cuando Terraform termine, ejecutar para obtener la URL pública:

```bash
terraform output -raw test_url
```

El balanceador puede tardar entre 2 y 10 minutos en propagar tras el primer
despliegue. Durante ese tiempo puede responder con `502` o `no healthy upstream`.

---

## Escenarios de evaluación

El único archivo que se debe editar entre escenarios es `terraform.tfvars`.
Después de cada cambio ejecutar `terraform apply`.

### Escenario 1 — Producción activa (100 % / 0 %)

Editar `terraform.tfvars`:

```hcl
main_traffic_weight        = 100
contingency_traffic_weight = 0
```

```bash
terraform apply
```

**Resultado esperado:** todas las peticiones muestran:

```
Bienvenido al Servicio Principal - Versión Producción
```

### Escenario 2 — Mantenimiento total (0 % / 100 %)

Editar `terraform.tfvars`:

```hcl
main_traffic_weight        = 0
contingency_traffic_weight = 100
```

```bash
terraform apply
```

**Resultado esperado:** todas las peticiones muestran:

```
Error 503 - Sitio en Mantenimiento Programado
```

### Escenario 3 — Balance equitativo (50 % / 50 %)

Editar `terraform.tfvars`:

```hcl
main_traffic_weight        = 50
contingency_traffic_weight = 50
```

```bash
terraform apply
```

**Resultado esperado:** peticiones consecutivas alternan entre ambos servicios.
La distribución es aproximada; una muestra de 100 peticiones suele dar entre
40/60 y 60/40 debido a varianza estadística normal.

> **Regla:** `main_traffic_weight + contingency_traffic_weight` debe ser
> siempre igual a 100. El código lo valida y falla con un error claro si no
> se cumple.

---

## Verificar la distribución de tráfico

```bash
IP=$(terraform output -raw load_balancer_ip)

for i in $(seq 1 30); do
  curl -s -H "Cache-Control: no-cache" "http://$IP/?r=$(date +%s%N)-$i" \
    | grep -oE "Bienvenido al Servicio Principal|Error 503"
done
```

---

## Evidencias

Todos los archivos de evidencia están en la carpeta `evidencias/`.

| Archivo | Contenido |
|---|---|
| `evidencias/evidencia-escenario-1.txt` | 20 peticiones → 100 % Producción |
| `evidencias/evidencia-escenario-2.txt` | 10 peticiones → 100 % Contingencia |
| `evidencias/evidencia-escenario-3.txt` | 100 peticiones → distribución 50/50 |
| `evidencias/evidencia-escenario-3-resumen.txt` | Resumen de conteos del Escenario 3 |
| `evidencias/evidencia-destroy1.png` | Captura de `terraform destroy` — inicio |
| `evidencias/evidencia-destroy2.png` | Captura de `terraform destroy` — completado |

---

## Limpieza obligatoria

Antes de la revisión, destruir todos los recursos:

```bash
terraform destroy
```

Escribir `yes` cuando Terraform lo solicite.

La consola de GCP debe quedar sin ningún recurso de este proyecto. Si quedan
recursos activos, el script de revisión automatizada intenta crearlos de nuevo
y falla por conflicto de nombres, lo que invalida la entrega.
