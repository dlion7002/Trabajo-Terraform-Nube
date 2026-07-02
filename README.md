# Proyecto Terraform - Balanceo de Trafico en GCP

Este proyecto despliega una arquitectura en Google Cloud Platform usando Terraform. La infraestructura permite controlar el trafico HTTP hacia dos servicios independientes usando un unico punto de entrada publico.

## Arquitectura

La solucion crea:

- Una red VPC personalizada.
- Una subred regional.
- Dos maquinas virtuales independientes:
  - Servicio Principal.
  - Servicio de Contingencia.
- Dos grupos de instancias independientes.
- Un balanceador HTTP externo global.
- Una unica direccion IP publica.
- Reglas de enrutamiento ponderado mediante variables de Terraform.

Los usuarios solo acceden a la IP publica del balanceador. Las maquinas virtuales no tienen IP publica.

## Servicios

Servicio Principal:

    Bienvenido al Servicio Principal - Versión Producción

Servicio de Contingencia:

    Error 503 - Sitio en Mantenimiento Programado

## Variables principales

Las variables que controlan la distribucion de trafico estan en terraform.tfvars:

    main_traffic_weight        = 100
    contingency_traffic_weight = 0

La suma de ambas variables debe ser igual a 100.

## Escenarios de evaluacion

Escenario 1 - Produccion activa:

    project_id = "project-c7fb6348-b503-457f-a32"
    main_traffic_weight        = 100
    contingency_traffic_weight = 0

Escenario 2 - Mantenimiento total:

    project_id = "project-c7fb6348-b503-457f-a32"
    main_traffic_weight        = 0
    contingency_traffic_weight = 100

Escenario 3 - Balance 50/50:

    project_id = "project-c7fb6348-b503-457f-a32"
    main_traffic_weight        = 50
    contingency_traffic_weight = 50

Aplicar cambios:

    terraform apply

Obtener URL:

    terraform output -raw test_url

Probar:

    URL=$(terraform output -raw test_url)

    for i in {1..30}; do
      curl -s -H "Cache-Control: no-cache" "$URL?request=$(date +%s%N)-$i" | grep -E "Bienvenido|Error 503"
    done

## Evidencias

Durante las pruebas se generaron archivos de evidencia:

- evidencia-escenario-2.txt
- evidencia-escenario-3.txt
- evidencia-escenario-3-resumen.txt

## Limpieza de recursos

Es obligatorio destruir los recursos despues de las pruebas para evitar costos y conflictos durante la revision.

    terraform destroy

Cuando Terraform solicite confirmacion, escribir:

    yes

Guardar captura de pantalla del resultado exitoso de terraform destroy.

## Antes de entregar

Ejecutar:

    terraform fmt
    terraform validate

El repositorio no debe incluir:

- .terraform/
- terraform.tfstate
- terraform.tfstate.backup
