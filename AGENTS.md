# Guia para Agentes LLM

Este repositorio contiene una solucion Terraform para desplegar una arquitectura de balanceo HTTP en Google Cloud Platform.

## Objetivo del proyecto

El objetivo es demostrar control de trafico por variables usando Terraform. La infraestructura permite enviar trafico a un servicio principal o a un servicio de contingencia mediante pesos configurables.

## Archivos importantes

- versions.tf: define Terraform, proveedor Google y configuracion del provider.
- variables.tf: define variables de proyecto, region, zona, maquina y pesos de trafico.
- terraform.tfvars: contiene los valores modificables para los escenarios.
- main.tf: contiene la infraestructura GCP completa.
- outputs.tf: imprime la IP publica y URL de prueba.
- README.md: explica ejecucion, pruebas y limpieza.

## Comportamiento esperado

Hay dos servicios independientes.

Servicio Principal:

- VM independiente.
- Grupo de instancia propio.
- Mensaje: Bienvenido al Servicio Principal - Versión Producción.

Servicio de Contingencia:

- VM independiente.
- Grupo de instancia propio.
- Mensaje: Error 503 - Sitio en Mantenimiento Programado.

Los usuarios solo acceden a una IP publica creada por el balanceador HTTP externo.

## Variables de trafico

Variables clave:

    main_traffic_weight        = 100
    contingency_traffic_weight = 0

La suma debe ser exactamente 100.

Escenarios:

- Produccion activa: 100 y 0.
- Mantenimiento total: 0 y 100.
- Balance equitativo: 50 y 50.

## Restricciones importantes

- No se deben configurar recursos manualmente despues de terraform apply.
- No se debe usar SSH para instalar o editar servicios.
- Las paginas web se crean con scripts de arranque de las VMs.
- Las VMs de produccion y contingencia deben ser recursos separados.
- No se debe reemplazar la arquitectura por una sola VM con dos rutas.
- El profesor debe poder cambiar solo terraform.tfvars y ejecutar terraform apply.

## Comandos de validacion

    terraform fmt
    terraform validate
    terraform apply
    terraform output -raw test_url

## Comando de limpieza

    terraform destroy

Despues de destruir, no deben quedar recursos creados por este proyecto.
