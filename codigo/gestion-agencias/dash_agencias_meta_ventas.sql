-- =====================================================================
-- DASHBOARD GESTIÓN AGENCIAS · META DE VENTAS
-- Tabla en Power BI: dash_agencias_meta_ventas (consulta nativa, sin tabla en db_tmp)
-- Fuente: dwh_prod.db_silver.file_presupuesto_ventas_formateado
--         (la misma meta que usa el Dashboard Ejecutivo de Ventas)
-- Grano: 1 fila por mes, tipo de punto (AGENCIA / ISLA) y ciudad
-- Negocio: solo Internet Residencial (es el único con meta 2026 para el canal)
-- Ciudad: en mayúsculas, para relacionarla con dash_agencias_ventas[ciudad] (CIUDAD_PRODUCTO)
-- Nota: Meta_dolores viene vacía desde mayo 2026; la meta en $ se calcula en Power BI
-- =====================================================================
SELECT
    CAST(DATE_TRUNC('MONTH', p.fecha_format) AS DATE)   AS Mes,
    p.canalVenta                                       AS tipo_punto,      -- AGENCIA / ISLA
    UPPER(TRIM(p.ciudad))                              AS ciudad,
    SUM(p.Meta)                                        AS meta,
    SUM(p.Meta_dolores)                                AS meta_usd,
    CURRENT_TIMESTAMP()                                AS fecha_actualizacion
FROM dwh_prod.db_silver.file_presupuesto_ventas_formateado p
WHERE p.canalVenta IN ('AGENCIA', 'ISLA')
  AND p.negocioCalculado = 'Internet Residencial'
  AND p.fecha_format >= '2026-01-01'
GROUP BY 1, 2, 3
HAVING SUM(p.Meta) > 0
