-- =====================================================================
-- DASHBOARD GESTIÓN AGENCIAS · BLOQUE INTERACCIONES CRM
-- Tabla en Power BI: dash_agencias_interacciones (consulta nativa, sin tabla en db_tmp)
-- Grano: 1 fila por registro de crm_interacciones del canal Agencia, desde enero 2026
--        SIN quitar duplicados: un mismo ID puede traer varias filas (un motivo por fila o el
--        mismo motivo registrado más de una vez); todas se cuentan, igual que en el CRM.
-- Canal Agencia = CANAL IN ('Agencia','Retencionestelco','Centro de Experiencia')
-- Tipologías    = SERVICIO_TIPO IN ('Solicitudes','Consultas','Problemas','Deserciones')
--                 + "Ventas": SOLUCION "SE REALIZÓ EL CAMBIO DE PLAN" solo hasta jul-2026 (antes no existía el detalle)
--                   o "... UPSELL / DOWNSELL / CROSSELL" (desde ago-2026).
--                   Se reclasifican desde su SERVICIO_TIPO original, así el total no cambia.
--                   "CAMBIO DE PLAN: UP/DOWN" (en Deserciones) es retención y NO cuenta como venta.
--        (una misma llamada / CALL_LOG_ID puede tener varias tipificaciones)
--
-- Banderas operativas:
--   es_caso_bo            = la SOLUCION menciona BO como palabra ("SE GENERÓ TICKET A BO", etc.; no cuenta TV BOX ni BONO)
--   es_escalado_n2        = ticket a BO, escalado con supervisor o ticket a jefe de agencia
--   genera_os             = se ingresó orden de servicio (ORDER_FSM o solución "SE INGRESÓ OS")
--   resuelto_1er_contacto = no escalado a N2, sin orden de servicio y sin "cliente volverá a llamar"
--
-- Contacto previo en otro canal (identificador único = cuenta del cliente):
--   para cada transacción de agencia se busca si la MISMA CUENTA tuvo una interacción CRM
--   en otro canal de atención al cliente en los 30 días ANTERIORES a la transacción
--   Canal Call Center (definición del área, canal_previo = 'Call Center'):
--     Back Office-TNS, Call Center, Cancelaciones-TNS, Coordinador-TNS, Corporativo Empresa,
--     RedesSociales, Retenciones, Supervisor-TNS, Telenews Omnicanal
--     (canal_previo_detalle guarda el canal exacto del CRM)
--   No cuentan: BackOfficeTVC, 360, Contratistas y registros sin canal
--   contacto_previo_30d   = 1 si tuvo al menos un contacto en esos canales
--   canal_previo          = grupo del ÚLTIMO contacto antes de la transacción
--   dias_contacto_previo  = días entre ese último contacto y la transacción de agencia
--   contactos_previos_30d = número de contactos en otros canales en los 30 días
-- =====================================================================
WITH base AS (
    SELECT
        ci.ID,
        TRIM(CAST(ci.ACCOUNT_ID AS STRING))                                        AS Cuenta,
        ci.CALL_LOG_ID,
        ci.CANAL                                                                   AS Canal,
        ci.FECHA_CREACION,
        ci.FECHA_CIERRE,
        DATE(ci.FECHA_CREACION)                                                    AS Fecha,
        CAST(DATE_TRUNC('MONTH', ci.FECHA_CREACION) AS DATE)                       AS Mes,
        TRIM(ci.AGENCIA)                                                           AS agencia,
        TRIM(ci.CIUDAD)                                                            AS ciudad_cliente,
        LOWER(TRIM(ci.USUARIO))                                                    AS usuario,
        CASE WHEN LOWER(TRIM(ci.USUARIO)) LIKE 'telco\\_%' ESCAPE '\\'
             THEN LOWER(TRIM(ci.USUARIO))
             ELSE CONCAT('telco_', LOWER(TRIM(ci.USUARIO))) END                    AS Asesor,
        ci.AGENTE_ID,
        TRIM(ci.SERVICIO_TIPO)                                                     AS Tipologia,
        UPPER(TRIM(REGEXP_REPLACE(ci.PROBLEMA,   '[\\r\\n]+', '')))                AS Problema,
        UPPER(TRIM(REGEXP_REPLACE(ci.ESPECIFICO, '[\\r\\n]+', '')))                AS Especifico,
        UPPER(TRIM(REGEXP_REPLACE(ci.CAUSA,      '[\\r\\n]+', '')))                AS Causa,
        UPPER(TRIM(REGEXP_REPLACE(ci.SOLUCION,   '[\\r\\n]+', '')))                AS Solucion,
        ci.ORDER_FSM,
        ci.TIPO_NEGOCIO,
        ci.categoria                                                               AS Categoria,
        ci.tecnologia_acceso                                                       AS Tecnologia_Acceso,
        ci.DURACION                                                                AS duracion_seg,
        -- Ventas: cambio de plan realizado (con o sin detalle Upsell / Downsell / Crossell)
        CASE WHEN (UPPER(TRIM(ci.SOLUCION)) LIKE 'SE REALIZ_ EL CAMBIO DE PLAN%' AND ci.FECHA_CREACION < '2026-08-01')
               OR UPPER(ci.SOLUCION) LIKE '%UPSELL%'
               OR UPPER(ci.SOLUCION) LIKE '%DOWNSELL%'
               OR UPPER(ci.SOLUCION) LIKE '%CROS%SEL%'
             THEN 1 ELSE 0 END                                                     AS es_venta,
        CASE WHEN UPPER(ci.SOLUCION) LIKE '%UPSELL%'     THEN 'Upsell'
             WHEN UPPER(ci.SOLUCION) LIKE '%DOWNSELL%'   THEN 'Downsell'
             WHEN UPPER(ci.SOLUCION) LIKE '%CROS%SEL%' THEN 'Crossell'
             WHEN UPPER(TRIM(ci.SOLUCION)) LIKE 'SE REALIZ_ EL CAMBIO DE PLAN%' AND ci.FECHA_CREACION < '2026-08-01' THEN 'Sin detalle'
        END                                                                        AS tipo_venta
    FROM dwh_prod.db_gold.crm_interacciones ci
    WHERE ci.CANAL IN ('Agencia', 'Retencionestelco', 'Centro de Experiencia')
      AND TRIM(ci.SERVICIO_TIPO) IN ('Solicitudes', 'Consultas', 'Problemas', 'Deserciones')
      AND ci.FECHA_CREACION >= '2026-01-01'
),
-- Transacciones de agencia (una por ID y fecha) para buscar el contacto previo
trans_agencia AS (
    SELECT DISTINCT
        b.ID,
        b.FECHA_CREACION,
        CAST(TRY_CAST(b.Cuenta AS DECIMAL(38,0)) AS STRING)                        AS cuenta_key
    FROM base b
    WHERE b.Cuenta IS NOT NULL
),
-- Contactos del cliente en otros canales de atención
otros_canales AS (
    SELECT
        CAST(TRY_CAST(ci.ACCOUNT_ID AS DECIMAL(38,0)) AS STRING)                   AS cuenta_key,
        ci.FECHA_CREACION                                                          AS fecha_otro,
        ci.CANAL                                                                   AS canal_otro_detalle,
        'Call Center'                                                              AS canal_otro
    FROM dwh_prod.db_gold.crm_interacciones ci
    WHERE ci.CANAL IN ('Back Office-TNS', 'Call Center', 'Cancelaciones-TNS', 'Coordinador-TNS',
                       'Corporativo Empresa', 'RedesSociales', 'Retenciones', 'Supervisor-TNS',
                       'Telenews Omnicanal')
      AND ci.FECHA_CREACION >= '2025-12-01'
      AND ci.ACCOUNT_ID IS NOT NULL
),
contacto_previo AS (
    SELECT
        t.ID,
        t.FECHA_CREACION,
        MAX_BY(o.canal_otro, o.fecha_otro)                                         AS canal_previo,
        MAX_BY(o.canal_otro_detalle, o.fecha_otro)                                 AS canal_previo_detalle,
        DATEDIFF(DATE(t.FECHA_CREACION), DATE(MAX(o.fecha_otro)))                  AS dias_contacto_previo,
        COUNT(*)                                                                   AS contactos_previos_30d
    FROM trans_agencia t
    JOIN otros_canales o
      ON o.cuenta_key  = t.cuenta_key
     AND o.fecha_otro  <  t.FECHA_CREACION
     AND o.fecha_otro  >= t.FECHA_CREACION - INTERVAL 30 DAYS
    GROUP BY t.ID, t.FECHA_CREACION
)
SELECT
    b.*,
    -- Tipología para el tablero: Ventas (cambio de plan up/down/cross) o la tipología original del CRM
    CASE WHEN b.es_venta = 1 THEN 'Ventas' ELSE b.Tipologia END                    AS Tipologia_dashboard,
    -- Tipologías como banderas, excluyentes entre sí (suman el total de interacciones)
    CASE WHEN b.es_venta = 0 AND b.Tipologia = 'Consultas'   THEN 1 ELSE 0 END     AS es_consulta,
    CASE WHEN b.es_venta = 0 AND b.Tipologia = 'Solicitudes' THEN 1 ELSE 0 END     AS es_solicitud,
    CASE WHEN b.es_venta = 0 AND b.Tipologia = 'Problemas'   THEN 1 ELSE 0 END     AS es_problema,
    CASE WHEN b.es_venta = 0 AND b.Tipologia = 'Deserciones' THEN 1 ELSE 0 END     AS es_desercion,
    -- Banderas operativas (aproximadas)
    CASE WHEN b.Solucion RLIKE '(^|[^A-Z])BO([^A-Z]|$)' THEN 1 ELSE 0 END                    AS es_caso_bo,
    CASE WHEN b.Solucion RLIKE '(^|[^A-Z])BO([^A-Z]|$)'
           OR b.Solucion LIKE '%ESCALA CON SUPERVISOR%'
           OR b.Solucion LIKE '%TICKET A JEFE DE AGENCIA%'
         THEN 1 ELSE 0 END                                                         AS es_escalado_n2,
    CASE WHEN (b.ORDER_FSM IS NOT NULL AND TRIM(b.ORDER_FSM) NOT IN ('', 'null'))
           OR b.Solucion LIKE '%INGRES% OS%'
         THEN 1 ELSE 0 END                                                         AS genera_os,
    CASE WHEN b.Solucion RLIKE '(^|[^A-Z])BO([^A-Z]|$)'
           OR b.Solucion LIKE '%ESCALA CON SUPERVISOR%'
           OR b.Solucion LIKE '%TICKET A JEFE DE AGENCIA%'
           OR (b.ORDER_FSM IS NOT NULL AND TRIM(b.ORDER_FSM) NOT IN ('', 'null'))
           OR b.Solucion LIKE '%INGRES% OS%'
           OR b.Solucion LIKE '%VOLVER_ A LLAMAR%'
         THEN 0 ELSE 1 END                                                         AS resuelto_1er_contacto,
    ROUND((UNIX_TIMESTAMP(b.FECHA_CIERRE) - UNIX_TIMESTAMP(b.FECHA_CREACION)) / 60.0, 2) AS minutos_registro,
    -- Contacto previo en otro canal (30 días antes de la transacción de agencia)
    CASE WHEN cp.ID IS NOT NULL THEN 1 ELSE 0 END                                  AS contacto_previo_30d,
    COALESCE(cp.canal_previo, 'Sin contacto previo')                               AS canal_previo,
    cp.canal_previo_detalle,
    cp.dias_contacto_previo,
    COALESCE(cp.contactos_previos_30d, 0)                                          AS contactos_previos_30d,
    CURRENT_TIMESTAMP()                                                            AS fecha_actualizacion
FROM base b
LEFT JOIN contacto_previo cp
  ON cp.ID             = b.ID
 AND cp.FECHA_CREACION = b.FECHA_CREACION
