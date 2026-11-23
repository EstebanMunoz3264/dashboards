-- =====================================================================
-- DASHBOARD GESTIÓN AGENCIAS · TIEMPO DE SOLUCIÓN CASOS N2
-- Tabla en Power BI: dash_agencias_tickets_bo (consulta nativa, sin tabla en db_tmp)
-- Fuente: dwh_prod.db_gold.resumen_tickets_back_office
-- Grano: 1 fila por ticket creado por un asesor del canal Agencia, desde enero 2026
--
-- Canal Agencia: se identifica por el USUARIO CREADOR (creado_por), no por el campo canal,
--   porque los tickets pendientes y parte de los terminados vienen con canal = 'Sin Registro'.
--   Asesor de agencia = usuario presente en dash_agencias_interacciones
--   (canales Agencia, Retencionestelco, Centro de Experiencia). (se calcula dentro de esta misma consulta).
--   Validación oct-2026: 802 tickets BO creados por asesores de agencia vs 795 casos BO en el CRM.
--
-- Caso N2 = finalización con ticket a BO, ticket a jefe de agencia o escalado con supervisor
-- Tiempo de solución N2 = horas_laborables de los casos N2 TERMINADOS
-- Pendientes = casos N2 aún abiertos (estado distinto de Terminado / Finalizado / Mal derivado)
-- Agencia = agencia donde el asesor registra más interacciones en el CRM
-- =====================================================================
WITH asesor_agencia AS (
    -- Asesores del canal y su agencia principal según sus interacciones del CRM
    SELECT Asesor, agencia
    FROM (
        SELECT CASE WHEN LOWER(TRIM(ci.USUARIO)) LIKE 'telco\\_%' ESCAPE '\\'
                    THEN LOWER(TRIM(ci.USUARIO))
                    ELSE CONCAT('telco_', LOWER(TRIM(ci.USUARIO))) END AS Asesor,
               TRIM(ci.AGENCIA)                                       AS agencia,
               COUNT(*)                                               AS n
        FROM dwh_prod.db_gold.crm_interacciones ci
        WHERE ci.CANAL IN ('Agencia', 'Retencionestelco', 'Centro de Experiencia')
          AND TRIM(ci.SERVICIO_TIPO) IN ('Solicitudes', 'Consultas', 'Problemas', 'Deserciones')
          AND ci.FECHA_CREACION >= '2026-01-01'
        GROUP BY 1, 2
    )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY Asesor ORDER BY n DESC, agencia) = 1
),
tickets AS (
    SELECT
        r.ticket,
        r.fecha_creacion,
        r.fecha_modificacion                                                   AS fecha_ultima_modificacion,
        DATE(r.fecha_creacion)                                                 AS Fecha,
        CAST(DATE_TRUNC('MONTH', r.fecha_creacion) AS DATE)                    AS Mes,
        r.canal                                                                AS canal_ticket,
        r.estado,
        r.servicio,
        r.servicio_tipo                                                        AS Tipologia,
        r.problemas_tipo,
        r.especificamente,
        r.finalizacion,
        r.motivo_operaciones,
        r.cuenta                                                               AS Cuenta,
        UPPER(TRIM(r.ciudad))                                                  AS ciudad_cliente,
        CASE WHEN LOWER(TRIM(r.creado_por)) LIKE 'telco\\_%' ESCAPE '\\'
             THEN LOWER(TRIM(r.creado_por))
             ELSE CONCAT('telco_', LOWER(TRIM(r.creado_por))) END              AS Asesor,
        LOWER(TRIM(r.asignado_a))                                              AS asignado_bo,
        r.horas_laborables,
        r.dias,
        r.rangos
    FROM dwh_prod.db_gold.resumen_tickets_back_office r
    WHERE r.fecha_creacion >= '2026-01-01'
)
SELECT
    t.*,
    COALESCE(a.agencia, 'Sin agencia')                                         AS agencia,
    CASE WHEN UPPER(t.finalizacion) RLIKE '(^|[^A-Z])BO([^A-Z]|$)'
           OR UPPER(t.finalizacion) LIKE '%JEFE DE AGENCIA%'
           OR UPPER(t.finalizacion) LIKE '%ESCALA CON SUPERVISOR%'
         THEN 1 ELSE 0 END                                                     AS es_caso_n2,
    CASE WHEN UPPER(t.finalizacion) RLIKE '(^|[^A-Z])BO([^A-Z]|$)' THEN 1 ELSE 0 END AS es_ticket_bo,
    CASE WHEN t.estado LIKE 'Terminado%' OR t.estado LIKE 'Finalizado%' THEN 1 ELSE 0 END AS terminado,
    CASE WHEN t.estado LIKE 'Pendiente%' THEN 1 ELSE 0 END                     AS pendiente,
    CASE WHEN t.estado = 'Mal derivado' THEN 1 ELSE 0 END                      AS mal_derivado,
    CASE WHEN (t.estado LIKE 'Terminado%' OR t.estado LIKE 'Finalizado%')
          AND t.rangos = 'Resuelto en menos de 24h' THEN 1 ELSE 0 END          AS resuelto_24h,
    CURRENT_TIMESTAMP()                                                        AS fecha_actualizacion
FROM tickets t
INNER JOIN asesor_agencia a                       -- solo tickets creados por asesores del canal Agencia
        ON a.Asesor = t.Asesor
