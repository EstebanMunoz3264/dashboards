-- =====================================================================
-- DASHBOARD GESTIÓN AGENCIAS · BLOQUE VENTAS
-- Tabla en Power BI: dash_agencias_ventas (consulta nativa, sin tabla en db_tmp)
-- Fuente ÚNICA: dwh_prod.db_gold.vw_ventas_comerciales (sin cruces con otras tablas)
-- Grano: 1 fila por ítem vendido (CITEM_ID) del canal Agencia e Islas, desde enero 2026
-- Canal: CANAL_VENTA_CELULA = 'AGENCIA'  (incluye SUBCANAL 'AGENCIA' y 'ISLA')
-- Fecha de la venta: FECHA_INSTALACION (igual que el Indicador Ejecutivo de Ventas);
--                    solo ventas instaladas. FECHA_CONTRATACION se conserva como referencia
--
-- Ventas realizadas  = ítems de Internet Residencial (es_internet = 1), igual que el
--                      Dashboard Ejecutivo de Ventas (NEGOCIOCALCULADO = 'Internet Residencial')
-- Valor vendido      = PRECIO_BASE de Internet Residencial (tarifa regular sin promo)
-- Ciudad             = CIUDAD_PRODUCTO (misma ciudad con la que se asigna la meta)
-- Asesor             = nombre del vendedor (VENDEDOR_PRODUCTO sin "(ASESOR INTEGRAL)")
-- Punto de venta     = Isla: nombre del centro comercial (campo ISLA)
--                      Agencia: la vista no trae el nombre de la agencia; se aproxima con
--                      la ciudad de producto más frecuente del vendedor en el mes
-- =====================================================================
WITH ventas AS (
    SELECT
        v.CITEM_ID,
        v.CONTRACT_ID,
        TRIM(CAST(v.ACCOUNT_ID AS STRING))                                     AS Cuenta,
        v.FECHA_CONTRATACION,
        DATE(v.FECHA_INSTALACION)                                              AS Fecha,
        CAST(DATE_TRUNC('MONTH', v.FECHA_INSTALACION) AS DATE)                 AS Mes,
        v.SUBCANAL                                                             AS tipo_punto,      -- AGENCIA / ISLA
        CASE WHEN v.SUBCANAL = 'ISLA' THEN TRIM(v.ISLA) END                    AS isla_nombre,
        TRIM(REGEXP_REPLACE(UPPER(v.VENDEDOR_PRODUCTO), '\\s*\\(ASESOR INTEGRAL\\)', '')) AS Asesor,
        v.ID_VENDEDOR_PRODUCTO,
        v.CEDULA_VENDEDOR,
        v.JEFE_VENTA,
        UPPER(TRIM(v.CIUDAD_PRODUCTO))                                         AS ciudad,
        v.CIUDAD_INSTALACION,
        v.REGION,
        v.REGION_PRINCIPAL,
        v.ZONA,
        v.SEGMENTO_NEGOCIO,
        v.PRODUCTO,
        v.PLAN_PRODUCTO,
        v.VARIANTE_PRODUCTO,
        v.TECNOLOGIA_ACCESO,
        v.VELOCIDAD_CONTRATADA,
        v.FORMA_PAGO,
        v.INSTALACION,
        v.FECHA_INSTALACION,
        v.DENTRO_SLA,
        v.ESTADO_PRODUCTO_ACTUAL,
        v.FECHA_TERMINACION_ACTUAL,
        v.PRECIO_BASE,
        v.PRECIO_PROMO,
        v.PRECIO_VENTA
    FROM dwh_prod.db_gold.vw_ventas_comerciales v
    WHERE v.CANAL_VENTA_CELULA = 'AGENCIA'
      AND v.FECHA_INSTALACION >= '2026-01-01'
),
-- Ciudad más frecuente de cada vendedor de agencia en el mes (aproximación a su agencia)
ciudad_vendedor AS (
    SELECT Asesor, Mes, ciudad AS ciudad_agencia
    FROM (
        SELECT Asesor, Mes, ciudad, COUNT(*) AS n
        FROM ventas
        WHERE tipo_punto = 'AGENCIA'
        GROUP BY Asesor, Mes, ciudad
    )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY Asesor, Mes ORDER BY n DESC, ciudad) = 1
)
SELECT
    v.*,
    CASE WHEN v.tipo_punto = 'ISLA' THEN v.isla_nombre
         ELSE INITCAP(c.ciudad_agencia) END                                    AS punto_venta,
    CASE WHEN v.SEGMENTO_NEGOCIO = 'Internet Residencial' THEN 1 ELSE 0 END    AS es_internet,
    CASE WHEN v.SEGMENTO_NEGOCIO = 'Internet Residencial'
         THEN COALESCE(v.PRECIO_BASE, 0) ELSE 0 END                            AS valor_vendido,
    CASE WHEN v.INSTALACION = 'SI' THEN 1 ELSE 0 END                           AS instalada,
    CASE WHEN v.ESTADO_PRODUCTO_ACTUAL = 'TERMINADO' THEN 1 ELSE 0 END         AS terminada_hoy,
    CURRENT_TIMESTAMP()                                                        AS fecha_actualizacion
FROM ventas v
LEFT JOIN ciudad_vendedor c
       ON c.Asesor = v.Asesor AND c.Mes = v.Mes
