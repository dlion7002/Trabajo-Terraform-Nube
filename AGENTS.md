# AGENTS.md — Guía para Agentes LLM

Este documento está dirigido a agentes LLM que necesiten auditar, desplegar,
modificar o verificar este proyecto. Explica la arquitectura, las decisiones de
diseño, el flujo de datos y los procedimientos de validación.

---

## 1. Qué hace este proyecto

Despliega en Google Cloud Platform una infraestructura HTTP con **un único punto
de entrada público** (IP global estática) que distribuye tráfico hacia dos
servicios web independientes. La proporción del tráfico se controla
exclusivamente cambiando dos números en `terraform.tfvars` y ejecutando
`terraform apply`. No se requiere ninguna intervención manual en la consola de
GCP ni acceso SSH a las VMs.

**Servicio Principal** responde con:
```
Bienvenido al Servicio Principal - Versión Producción
```

**Servicio de Contingencia** responde con:
```
Error 503 - Sitio en Mantenimiento Programado
```

---

## 2. Mapa de archivos

```
.
├── versions.tf          # Versión mínima de Terraform y proveedor Google (~> 6.0)
├── variables.tf         # Declaración de todas las variables con tipos y validaciones
├── terraform.tfvars     # Valores concretos: project_id y pesos de tráfico
├── main.tf              # Todos los recursos GCP (red, VMs, LB)
├── outputs.tf           # IP pública, URL de prueba, pesos activos
├── .gitignore           # Excluye tfstate y backups
├── .terraform.lock.hcl  # Lock del proveedor (garantiza reproducibilidad)
├── README.md            # Manual para humanos
└── evidencia-*.txt      # Logs de curl que demuestran los 3 escenarios
```

`main.tf` contiene toda la infraestructura en un solo archivo. No hay módulos
externos ni backends remotos; el estado se guarda localmente en `terraform.tfstate`
(excluido de git).

---

## 3. Arquitectura y grafo de dependencias

```
Internet
    │  HTTP :80
    ▼
google_compute_global_forwarding_rule.http_forwarding_rule
    │  usa ip_address de
    ├──► google_compute_global_address.public_ip
    │
    │  apunta a
    ▼
google_compute_target_http_proxy.http_proxy
    │  referencia url_map
    ▼
google_compute_url_map.url_map
    │  default_route_action → weighted_backend_services
    │
    ├──► google_compute_backend_service.main_backend  (weight = var.main_traffic_weight)
    │         │  health_checks
    │         ├──► google_compute_health_check.http
    │         │  backend.group
    │         └──► google_compute_instance_group.main_group
    │                   │  instances
    │                   └──► google_compute_instance.main_service  (VM e2-micro)
    │                             │  subnetwork
    │                             └──► google_compute_subnetwork.subnet
    │                                       │  network
    │                                       └──► google_compute_network.vpc
    │
    └──► google_compute_backend_service.contingency_backend  (weight = var.contingency_traffic_weight)
              │  (misma cadena: health_check → instance_group → VM → subnet → vpc)
              └──► google_compute_instance_group.contingency_group
                        └──► google_compute_instance.contingency_service  (VM e2-micro)

google_compute_firewall.allow_lb_http
    │  aplica sobre la VPC
    └──► permite TCP:80 desde 35.191.0.0/16 y 130.211.0.0/22 (rangos de health checks de GCP)
         hacia instancias con tag "tf-traffic-project-web"
```

**Recursos totales:** 14 (2 VMs, 2 instance groups, 2 backend services, 1 health
check, 1 URL map, 1 HTTP proxy, 1 IP global, 1 forwarding rule, 1 VPC, 1 subnet,
1 firewall rule).

---

## 4. Flujo del control de tráfico

El único mecanismo de control de tráfico es el bloque
`default_route_action.weighted_backend_services` dentro del URL map:

```
terraform.tfvars
  main_traffic_weight        = 50   ──►  variables.tf (var.main_traffic_weight)
  contingency_traffic_weight = 50   ──►  variables.tf (var.contingency_traffic_weight)
                                              │
                                              ▼
                                    main.tf → google_compute_url_map.url_map
                                      default_route_action {
                                        weighted_backend_services {
                                          weight = var.main_traffic_weight        # 50
                                        }
                                        weighted_backend_services {
                                          weight = var.contingency_traffic_weight # 50
                                        }
                                      }
```

GCP interpreta los pesos como proporciones relativas, no porcentajes absolutos.
Con 50/50 cada servicio recibe aproximadamente el 50% del tráfico. Con 100/0
todo va al servicio principal. Con 0/100 todo va a contingencia.

**Restricción activa en el código:** un `lifecycle.precondition` en el URL map
exige que `main_traffic_weight + contingency_traffic_weight == 100`. Si no se
cumple, `terraform apply` falla con un error descriptivo antes de crear o
modificar cualquier recurso.

**Cambiar el escenario activo requiere exactamente dos pasos:**
1. Editar `terraform.tfvars` con los nuevos valores.
2. Ejecutar `terraform apply`.

No se debe tocar ningún archivo `.tf`.

---

## 5. Cómo funcionan los servidores web (startup scripts)

Las VMs no tienen IP pública y no se configuran por SSH. El servidor web se
despliega automáticamente mediante `metadata_startup_script` en el recurso
`google_compute_instance`. El script se ejecuta una sola vez al arrancar la VM.

El script realiza tres acciones:
1. Escribe `/opt/traffic-service/server.py` — un servidor HTTP mínimo en Python 3
   (disponible en Debian 12 sin instalar paquetes adicionales).
2. Escribe `/etc/systemd/system/traffic-service.service` — una unidad systemd
   que mantiene el servidor corriendo y lo reinicia si falla.
3. Habilita e inicia el servicio con `systemctl`.

El servidor Python responde a cualquier ruta GET con un HTML que contiene el
mensaje del enunciado en un `<h1>`. Incluye cabeceras `Cache-Control: no-store`
para garantizar que las pruebas de balanceo no sean afectadas por caché del
cliente o del navegador.

El heredoc `<<-SCRIPT` (con guión) en HCL elimina la indentación de espacios del
contenido antes de enviarlo a GCP, por lo que el Python generado tiene
indentación correcta en columna 0.

---

## 6. Decisiones de diseño relevantes

| Decisión | Alternativa descartada | Razón |
|---|---|---|
| `load_balancing_scheme = "EXTERNAL_MANAGED"` | `EXTERNAL` (clásico) | Solo `EXTERNAL_MANAGED` soporta `weighted_backend_services` con `default_route_action` |
| `default_route_action` en el URL map | `route_rules` con `path_matcher` | Más simple para enrutamiento global sin distinción de rutas |
| Servidor Python 3 built-in | nginx | No requiere `apt-get`, elimina la dependencia de internet en el startup script |
| Sin `access_config {}` en las VMs | VMs con IP pública efímera | Seguridad: las VMs son inaccesibles desde internet directamente; solo el LB las alcanza |
| Firewall solo a rangos `35.191.0.0/16` y `130.211.0.0/22` | `0.0.0.0/0` | Esos son los rangos oficiales de los proxies de GCP; no es necesario abrir el mundo |
| `lifecycle.precondition` para suma == 100 | Sin validación | Falla rápido con mensaje claro en lugar de crear recursos con comportamiento inesperado |
| `name_prefix` como variable | Nombres hardcodeados | Permite limpiar conflictos de nombres simplemente cambiando el prefijo |

---

## 7. Variables

Todas las variables están declaradas en `variables.tf`. Las únicas que el
evaluador debe modificar están en `terraform.tfvars`.

| Variable | Tipo | Default | Propósito |
|---|---|---|---|
| `project_id` | string | — (requerida) | ID del proyecto GCP donde se despliega |
| `region` | string | `us-central1` | Región para la subred |
| `zone` | string | `us-central1-a` | Zona para las VMs e instance groups |
| `name_prefix` | string | `tf-traffic-project` | Prefijo de todos los nombres de recursos |
| `machine_type` | string | `e2-micro` | Tipo de VM (mínimo costo) |
| `main_traffic_weight` | number | `100` | Peso de tráfico al servicio principal (0–100) |
| `contingency_traffic_weight` | number | `0` | Peso de tráfico al servicio de contingencia (0–100) |

---

## 8. Los 3 escenarios de evaluación

Para cambiar de escenario: editar `terraform.tfvars` y ejecutar `terraform apply`.

### Escenario 1 — Producción activa (100 / 0)

```hcl
main_traffic_weight        = 100
contingency_traffic_weight = 0
```

Verificación esperada: 100% de las peticiones responden con
`"Bienvenido al Servicio Principal - Versión Producción"`.

### Escenario 2 — Mantenimiento total (0 / 100)

```hcl
main_traffic_weight        = 0
contingency_traffic_weight = 100
```

Verificación esperada: 100% de las peticiones responden con
`"Error 503 - Sitio en Mantenimiento Programado"`.

### Escenario 3 — Balance equitativo (50 / 50)

```hcl
main_traffic_weight        = 50
contingency_traffic_weight = 50
```

Verificación esperada: distribución aproximada 50/50 en un lote de peticiones.
La varianza estadística es normal; una muestra de 100 peticiones suele dar
entre 40/60 y 60/40. No se debe esperar exactamente 50/50 en cada petición.

---

## 9. Procedimiento completo de despliegue y verificación

```bash
# 1. Autenticarse con GCP
gcloud auth application-default login

# 2. Inicializar proveedores
terraform init

# 3. Revisar el plan (14 recursos a crear)
terraform plan

# 4. Desplegar
terraform apply

# 5. Obtener URL
terraform output -raw test_url

# 6. Esperar propagación del LB (2–10 minutos es normal)
# Verificar con:
curl http://<IP>/

# 7. Probar distribución de tráfico
IP=$(terraform output -raw load_balancer_ip)
for i in $(seq 1 20); do
  curl -s -H "Cache-Control: no-cache" "http://$IP/?r=$i" | grep -oE "Servicio Principal|Mantenimiento"
done

# 8. Cambiar escenario: editar terraform.tfvars y repetir desde paso 4

# 9. Al terminar, destruir todos los recursos
terraform destroy
```

---

## 10. Diagnóstico de problemas comunes

| Síntoma | Causa probable | Acción |
|---|---|---|
| `"no healthy upstream"` en el primer minuto | Propagación normal del LB global | Esperar 2–5 minutos y reintentar |
| `"no healthy upstream"` después de 10 minutos | Startup script falló; servidor Python no está corriendo | Ver logs de la VM en GCP Console → Compute Engine → VM → Serial port |
| Escenario 3 sigue mostrando 100% de un solo servicio | Propagación lenta del cambio de pesos | Esperar 2–3 minutos adicionales; el LB global tarda más en propagar que uno regional |
| `terraform apply` falla con `precondition` | Los pesos no suman 100 | Corregir `terraform.tfvars` |
| `terraform apply` falla con `Error 403` | Compute Engine API no habilitada o permisos insuficientes | Habilitar API en GCP Console o verificar rol IAM |
| `terraform apply` falla con nombre duplicado | Recursos de una ejecución anterior no destruidos | Ejecutar `terraform destroy` o limpiar manualmente en GCP Console |
| Las peticiones del escenario 3 siempre caen al mismo backend | Conexión HTTP keep-alive reutiliza la misma ruta | Usar `?r=$(date +%s%N)-$i` en la URL para forzar peticiones nuevas |

---

## 11. Requisitos de IAM (obligatorio para la revisión)

El evaluador del proyecto debe tener acceso al proyecto GCP con rol **Editor**
(`roles/editor`). Esto se configura en GCP Console → IAM y administración → IAM
→ Otorgar acceso.

Sin este acceso el evaluador no puede ejecutar `terraform apply` ni `terraform
destroy` usando sus propias credenciales sobre el proyecto del estudiante.

---

## 12. Restricciones de entrega

- `terraform.tfstate` y `terraform.tfstate.backup` no deben estar en el repositorio.
- El proyecto GCP debe estar **vacío de recursos** antes de la revisión (ejecutar
  `terraform destroy`). Si quedan recursos activos, el script de revisión
  automática falla por conflicto de nombres y la nota es cero.
- `project_id` debe ser una variable; no puede estar hardcodeado en ningún `.tf`.
- Toda la configuración de las VMs (instalación del servidor, contenido HTML)
  debe ocurrir en el startup script. No se acepta configuración post-deploy
  por SSH ni por consola web.
