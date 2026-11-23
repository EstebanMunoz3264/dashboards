-- =====================================================================
-- DASHBOARD GESTIÓN AGENCIAS · BLOQUE RETENCIÓN
-- Tabla en Power BI: dash_agencias_retencion (consulta nativa, sin tabla en db_tmp)
-- Grano: 1 fila por TICKET válido del canal Agencia, desde enero 2026 (sin deduplicar por cuenta)
-- Tickets rechazados: excluidos solo desde 2026-07-01 (enero-junio se mantienen, no retroactivo)
--
-- Valor económico rescatado = SUM(valor_rescatado)
--   valor_rescatado = arpu_neto_3m de la cuenta del ticket si quedó retenido (SI / SI CRM), 0 si no
--   arpu_neto_3m    = promedio mensual de la mensualidad NETA (NETINITAMOUNT, sin impuesto)
--                     de TODA la cuenta, facturas emitidas desde el mes -2 hasta la fecha del ticket
--                     (misma ventana y filtros de facturación que base_flujos_desercion)
-- =====================================================================
WITH
-- ---------------------------------------------------------------------
-- (1) Tickets de retención canal Agencia (todos los tickets válidos)
-- ---------------------------------------------------------------------
tickets AS (
    SELECT
        t.Ticket,
        TRIM(CAST(t.Cuenta AS STRING))                                     AS Cuenta,
        TRY_CAST(t.Cuenta AS DECIMAL(38,0))                                AS ACCOUNT_ID,
        t.Fecha_Llamada,
        DATE(t.Fecha_Llamada)                                              AS Fecha,
        CAST(DATE_TRUNC('MONTH', t.Fecha_Llamada) AS DATE)                 AS Mes,
        t.sucursal_agencia_id,
        t.agencia,
        t.AgenteCall,
        t.Grupo,
        t.Servicios,
        t.Servicios_a_Cancelar,
        t.Tipo_Cliente,
        t.Tipo_Solicitud,
        t.Motivo_Aparente,
        t.Motivo_Real,
        t.Retencion,
        t.estado_ticket,
        t.beneficios,
        t.num_beneficios,
        t.TECNOLOGIA_ACCESO,
        t.CIUDAD_INSTALACION,
        CASE WHEN t.Retencion IN ('SI', 'SI CRM') THEN 1 ELSE 0 END        AS retenido
    FROM dwh_prod.db_gold.tickets_deserciones t
    WHERE t.Departamento = 'Agencia'
      AND t.Fecha_Llamada >= '2026-01-01'
      AND t.Retencion IN ('SI', 'NO', 'SI CRM')
      -- Rechazados se excluyen solo desde julio 2026 (no retroactivo)
      AND NOT (
              t.Fecha_Llamada >= '2026-07-01'
          AND COALESCE(t.estado_ticket, '') IN ('Rechazado', 'Ticket Rechazado', 'Ticket rechazado')
      )
      AND t.Cuenta IS NOT NULL
),
-- ---------------------------------------------------------------------
-- (2) Facturación: mensualidades válidas TYTAN de las cuentas con ticket
--     (mismos filtros que base_flujos_desercion, sin restringir a Internet Residencial)
-- ---------------------------------------------------------------------
facturas AS (
    SELECT
        t.Ticket,
        CAST(DATE_TRUNC('MONTH', fa.FECHA_CREACION) AS DATE)               AS mes_fact,
        SUM(fa.NETINITAMOUNT)                                              AS neto_mes,
        SUM(fa.INITAMOUNT)                                                 AS con_imp_mes
    FROM dwh_prod.db_gold.facturacion fa
    JOIN tickets t
        ON  TRY_CAST(fa.CPARTYACCOUNT_ID AS DECIMAL(38,0)) = t.ACCOUNT_ID
        AND fa.FECHA_CREACION >= ADD_MONTHS(t.Mes, -2)
        AND fa.FECHA_CREACION <= t.Fecha_Llamada
    WHERE fa.SISTEMA       = 'TYTAN'
      AND fa.VALIDO        = 'TRUE'
      AND fa.ANULADO       = 'NO ANULADO'
      AND fa.CLASIFICACION = 'MENSUALIDAD'
      AND fa.TIPO_DOCF     = 'Factura'
      AND (fa.NOMBRE_RUBRO IS NULL OR fa.NOMBRE_RUBRO NOT LIKE '%REVISTA%')
      AND DATE_TRUNC('MONTH', fa.FECHA_CREACION) = DATE_TRUNC('MONTH', NVL(fa.DFROM, fa.FECHA_CREACION))
      AND fa.FECHA_CREACION >= '2025-11-01'
    GROUP BY t.Ticket, CAST(DATE_TRUNC('MONTH', fa.FECHA_CREACION) AS DATE)
    HAVING SUM(fa.NETINITAMOUNT) > 0
),
-- ---------------------------------------------------------------------
-- (3) ARPU 3m por ticket (ventana: mes -2 hasta la fecha del ticket)
-- ---------------------------------------------------------------------
arpu AS (
    SELECT
        Ticket,
        COUNT(*)                                                           AS meses_facturados_3m,
        ROUND(AVG(neto_mes), 2)                                            AS arpu_neto_3m,
        ROUND(AVG(con_imp_mes), 2)                                         AS arpu_imp_3m
    FROM facturas
    GROUP BY Ticket
)
SELECT
    t.Ticket,
    t.Cuenta,
    t.Fecha_Llamada,
    t.Fecha,
    t.Mes,
    t.sucursal_agencia_id,
    t.agencia,
    t.AgenteCall,
    t.Grupo,
    t.Servicios,
    t.Servicios_a_Cancelar,
    t.Tipo_Cliente,
    t.Tipo_Solicitud,
    t.Motivo_Aparente,
    t.Motivo_Real,
    t.Retencion,
    t.estado_ticket,
    t.beneficios,
    t.num_beneficios,
    t.TECNOLOGIA_ACCESO,
    t.CIUDAD_INSTALACION,
    t.retenido,
    COALESCE(a.meses_facturados_3m, 0)                                     AS meses_facturados_3m,
    a.arpu_neto_3m,
    a.arpu_imp_3m,
    CASE WHEN t.retenido = 1 THEN COALESCE(a.arpu_neto_3m, 0) ELSE 0 END   AS valor_rescatado,
    CASE WHEN a.arpu_neto_3m IS NULL THEN 'Sin facturación'
         WHEN a.arpu_neto_3m < 15    THEN '1. < $15'
         WHEN a.arpu_neto_3m < 20    THEN '2. $15-20'
         WHEN a.arpu_neto_3m < 25    THEN '3. $20-25'
         WHEN a.arpu_neto_3m < 30    THEN '4. $25-30'
         ELSE '5. >= $30' END                                              AS rango_arpu,
    CURRENT_TIMESTAMP()                                                    AS fecha_actualizacion
FROM tickets t
LEFT JOIN arpu a
       ON a.Ticket = t.Ticket
