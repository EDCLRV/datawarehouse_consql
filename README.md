# Proyecto de Data Warehouse

## Descripción

Este proyecto tiene como objetivo integrar, transformar y organizar datos de distintas fuentes en un Data Warehouse (almacén de datos), para facilitar su consulta, análisis y uso en reportes.

El repositorio organiza la documentación, las pruebas, los procesos de carga y los conjuntos de datos necesarios para desarrollar y mantener la solución.

## Objetivos

- Centralizar los datos relevantes para el análisis.
- Estandarizar formatos y aplicar reglas de calidad.
- Diseñar un modelo analítico basado en tablas de hechos y dimensiones.
- Automatizar los procesos de extracción, transformación y carga (ETL).
- Documentar las fuentes, las transformaciones y la estructura del almacén.
- Validar la integridad y la consistencia de los datos mediante pruebas.

## Estructura del repositorio

```text
datawarehouse/
├── README.md
├── docs/
│   ├── arquitectura.md
│   ├── fuentes_datos.md
│   ├── modelo_dimensional.md
│   ├── diccionario_datos.md
│   └── reglas_calidad.md
├── tests/
│   ├── test_transformaciones.py
│   ├── test_calidad_datos.py
│   └── test_integridad.py
├── scripts/
│   ├── sql/
│   │   ├── crear_esquemas.sql
│   │   ├── crear_dimensiones.sql
│   │   └── crear_hechos.sql
│   ├── extraer.py
│   ├── transformar.py
│   ├── cargar.py
│   └── ejecutar_etl.py
└── dataset/
    ├── raw/
    ├── processed/
    └── samples/
```

> La estructura y los nombres de archivo son una propuesta inicial; deben ajustarse a las fuentes, herramientas y necesidades del proyecto.

## Descripción de las carpetas

### `docs/`: documentación

Contiene la documentación funcional y técnica del proyecto.

- `arquitectura.md`: componentes, tecnologías seleccionadas y flujo de datos.
- `fuentes_datos.md`: origen, formato, periodicidad y condiciones de acceso de cada fuente.
- `modelo_dimensional.md`: tablas de hechos, dimensiones, relaciones y granularidad.
- `diccionario_datos.md`: definición, tipo, significado y restricciones de los campos.
- `reglas_calidad.md`: criterios de validación y tratamiento de errores.

### `tests/`: pruebas y validaciones

Agrupa las pruebas automatizadas para verificar las transformaciones y la calidad de los datos.

- `test_transformaciones.py`: comprueba las reglas de limpieza y transformación.
- `test_calidad_datos.py`: verifica campos obligatorios, duplicados, formatos y rangos permitidos.
- `test_integridad.py`: valida claves, relaciones entre tablas y consistencia de las cargas.

Las pruebas deberán incluir casos esperados, entradas inválidas y escenarios de error. Las herramientas de ejecución se definirán según la implementación.

### `scripts/`: procesamiento y carga

Contiene los scripts SQL y los programas que implementan el flujo ETL.

- `sql/`: creación de esquemas, dimensiones y tablas de hechos.
- `extraer.py`: obtiene los datos de las fuentes definidas.
- `transformar.py`: limpia, normaliza y aplica reglas de negocio.
- `cargar.py`: inserta o actualiza los datos en el almacén.
- `ejecutar_etl.py`: coordina las etapas del proceso y registra su resultado.

La implementación deberá contemplar registro de errores, trazabilidad de las ejecuciones y mecanismos para evitar duplicaciones al repetir una carga.

### `dataset/`: conjuntos de datos

Organiza los archivos utilizados durante el desarrollo y procesamiento.

- `raw/`: datos originales, conservados sin modificaciones.
- `processed/`: archivos resultantes de la limpieza y transformación, cuando sea necesario persistirlos.
- `samples/`: muestras pequeñas, anonimizadas o sintéticas para desarrollo y pruebas.

Esta carpeta no sustituye a la base de datos del Data Warehouse. Su función es almacenar archivos de entrada, resultados intermedios y muestras de trabajo.

## Flujo de procesamiento propuesto

1. Identificar y documentar las fuentes en `docs/`.
2. Extraer los datos y conservar los archivos originales en `dataset/raw/`, cuando corresponda.
3. Validar la estructura y los requisitos mínimos de los datos de entrada.
4. Limpiar y transformar los datos mediante los programas de `scripts/`.
5. Guardar resultados intermedios en `dataset/processed/`, si el proceso lo requiere.
6. Cargar primero las dimensiones y después las tablas de hechos, según sus dependencias.
7. Ejecutar las validaciones de calidad e integridad de `tests/`.
8. Registrar los resultados de la ejecución y actualizar la documentación cuando existan cambios.

## Configuración y ejecución

Antes de ejecutar el proyecto, se deberán definir y documentar:

- El motor de base de datos y su versión.
- La versión de Python y las dependencias necesarias, si se utiliza Python.
- Las credenciales y los parámetros de conexión mediante variables de entorno.
- Las fuentes de datos y sus permisos de acceso.
- El orden de ejecución de los scripts SQL y del proceso ETL.
- La herramienta y los comandos para ejecutar las pruebas.

Los comandos definitivos de instalación y ejecución se incorporarán cuando los scripts y sus dependencias estén implementados.

## Seguridad y gestión de datos

- No incorporar contraseñas, tokens ni credenciales al repositorio.
- Excluir del control de versiones los datos confidenciales y los archivos voluminosos mediante `.gitignore`.
- Utilizar muestras anonimizadas o sintéticas para pruebas compartidas.
- Documentar las restricciones de acceso, las licencias y los periodos de conservación de los datos.

## Entregables previstos

- Documentación de arquitectura, fuentes y modelo dimensional.
- Diccionario de datos y reglas de calidad.
- Scripts de creación y carga del Data Warehouse.
- Pruebas automatizadas de transformación, calidad e integridad.
- Muestras de datos para reproducir los casos de prueba.

## Estado del proyecto

Propuesta inicial de organización. Las tecnologías, las fuentes de datos y las reglas de negocio están pendientes de definición.
