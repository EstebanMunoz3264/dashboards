-- =====================================================================
-- DASHBOARD GESTIÓN AGENCIAS · BLOQUE TIEMPOS DE ATENCIÓN
-- Tabla en Power BI: dash_agencias_tiempos (consulta nativa, sin tabla en db_tmp)
-- Fuente: tablas silver del turnero (las mismas que usa la vista db_gold.vw_turnero)
--   turnos_turns, turnos_agencies, turnos_service_types, turnos_turn_statuses, turnos_agents
-- Grano: 1 fila por turno, desde enero 2026 (todos los estados; las medidas usan solo Completado)
--
-- Tiempos calculados desde las fechas (los campos tiempo_espera_real / duracion_servicio
-- cambian de minutos a segundos en feb-2026, por eso no se usan):
--   espera_min   = fecha_llamado    - fecha_creacion
--   atencion_min = fecha_completado - fecha_inicio
--
-- Agencia: desde el 02-jun-2026 los turnos llegan sin agency_id (turno por QR desde el celular).
--   Se completa con la agencia asignada al agente que atendió el turno (turnos_agents.agency_id);
--   si el agente no tiene agencia asignada, con la agencia donde más turnos atendió cuando
--   el turno sí traía agencia.
--   Validación ene-may 2026: la agencia del agente coincide con la del turno en el 94% de los casos.
--   Turnos sin agente (cancelados / no atendidos) o con agente sin agencia -> 'Sin agencia'.
-- Agente: nombre completo del agente (turnos_agents.full_name, desenmascarado nov-2026);
--   agente_id = id del agente (hay nombres repetidos con distinto usuario)
-- Espera negativa de hasta 5 min (registro segundos después del llamado) = 0 min de espera
-- Atípicos (espera o atención < 0 o > 8 h) se excluyen de promedios y del SLA
-- SLA: espera <= 10 minutos sobre turnos completados con espera válida
--      (ajustar el valor en la columna dentro_sla si cambia el objetivo)
-- =====================================================================
WITH agencia_hist AS (
    -- Agencia donde más turnos atendió cada agente cuando el turno traía agencia
    SELECT assigned_agent_id, agency_id AS agency_id_hist
    FROM (
        SELECT assigned_agent_id, agency_id, COUNT(*) AS n
        FROM dwh_prod.db_silver.turnos_turns
        WHERE agency_id IS NOT NULL AND assigned_agent_id IS NOT NULL
        GROUP BY assigned_agent_id, agency_id
    )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY assigned_agent_id ORDER BY n DESC, agency_id) = 1
),
turnos AS (
    SELECT
        t.id,
        t.turn_number                                                          AS numero_turno,
        t.agency_id                                                            AS agency_id_turno,
        age.agency_id                                                          AS agency_id_agente,
        h.agency_id_hist,
        t.assigned_agent_id,
        UPPER(TRIM(CAST(age.full_name AS STRING)))                             AS nombre_agente,
        age.username                                                           AS usuario_agente,
        st.name                                                                AS tipo_servicio,
        sta.status_name                                                        AS estado,
        t.client_type                                                          AS tipo_cliente,
        t.turn_type                                                            AS tipo_turno,
        t.is_new_client                                                        AS es_nuevo_cliente,
        t.is_urgent                                                            AS es_urgente,
        t.origin                                                               AS origen,
        t.access_channel                                                       AS canal_acceso,
        t.created_at                                                           AS fecha_creacion,
        t.called_at                                                            AS fecha_llamado,
        t.started_at                                                           AS fecha_inicio,
        t.completed_at                                                         AS fecha_completado
    FROM dwh_prod.db_silver.turnos_turns t
    LEFT JOIN dwh_prod.db_silver.turnos_service_types st  ON st.id  = t.service_type_id
    LEFT JOIN dwh_prod.db_silver.turnos_turn_statuses sta ON sta.id = t.current_status_id
    LEFT JOIN dwh_prod.db_silver.turnos_agents        age ON age.id = t.assigned_agent_id
    LEFT JOIN agencia_hist                                  h   ON h.assigned_agent_id = t.assigned_agent_id
    WHERE t.created_at >= '2026-01-01'
),
base AS (
    SELECT
        tu.id,
        tu.numero_turno,
        -- Nombre homologado con dim_agencias del tablero (sin Sucursal/CEDEX; Village Plaza -> Village)
        CASE WHEN a.name IS NULL OR TRIM(a.name) = '' THEN NULL
             WHEN UPPER(a.name) LIKE '%VILLAGE%' THEN 'Village'
             ELSE INITCAP(TRIM(REGEXP_REPLACE(TRIM(a.name), '(?i)^(sucursal|cedex)[\\s-]+', '')))
        END                                                                    AS agencia_origen,
        CASE WHEN UPPER(TRIM(a.city)) = 'RIOBAMABA' THEN 'RIOBAMBA'
             WHEN UPPER(TRIM(a.city)) = 'QUEVEDP'   THEN 'QUEVEDO'
             ELSE UPPER(TRIM(a.city)) END                                      AS ciudad_origen,
        CASE WHEN tu.agency_id_turno  IS NOT NULL THEN 'Turnero'
             WHEN tu.agency_id_agente IS NOT NULL AND a.id IS NOT NULL THEN 'Agencia del agente'
             WHEN a.id IS NOT NULL                THEN 'Histórico del agente'
             ELSE 'Sin agencia' END                                            AS origen_agencia,
        tu.nombre_agente                                                       AS agente,
        tu.assigned_agent_id                                                   AS agente_id,
        tu.usuario_agente,
        tu.tipo_servicio,
        tu.estado,
        tu.tipo_cliente,
        tu.tipo_turno,
        tu.es_nuevo_cliente,
        tu.es_urgente,
        tu.origen,
        tu.canal_acceso,
        tu.fecha_creacion,
        tu.fecha_llamado,
        tu.fecha_inicio,
        tu.fecha_completado,
        DATE(tu.fecha_creacion)                                                AS Fecha,
        CAST(DATE_TRUNC('MONTH', tu.fecha_creacion) AS DATE)                   AS Mes,
        HOUR(tu.fecha_creacion)                                                AS hora_llegada,
        -- Espera negativa de pocos segundos = turno registrado al momento de la atención -> 0 min
        CASE WHEN (UNIX_TIMESTAMP(tu.fecha_llamado) - UNIX_TIMESTAMP(tu.fecha_creacion)) BETWEEN -300 AND 0 THEN 0
             ELSE ROUND((UNIX_TIMESTAMP(tu.fecha_llamado) - UNIX_TIMESTAMP(tu.fecha_creacion)) / 60.0, 2)
        END                                                                    AS espera_min,
        ROUND((UNIX_TIMESTAMP(tu.fecha_llamado)    - UNIX_TIMESTAMP(tu.fecha_creacion)) / 60.0, 2) AS espera_min_original,
        ROUND((UNIX_TIMESTAMP(tu.fecha_completado) - UNIX_TIMESTAMP(tu.fecha_inicio))   / 60.0, 2) AS atencion_min
    FROM turnos tu
    LEFT JOIN dwh_prod.db_silver.turnos_agencies a
           ON a.id = COALESCE(tu.agency_id_turno, tu.agency_id_agente, tu.agency_id_hist)
)
SELECT
    b.*,
    COALESCE(b.agencia_origen, 'Sin agencia')                                  AS agencia,
    COALESCE(b.ciudad_origen,  'SIN CIUDAD')                                   AS ciudad_agencia,
    CASE WHEN b.estado = 'Completado' THEN 1 ELSE 0 END                        AS completado,
    CASE WHEN b.estado = 'Cancelado'  THEN 1 ELSE 0 END                        AS cancelado,
    -- Tiempos válidos: completados, no negativos y <= 8 horas (excluye turnos dejados abiertos)
    CASE WHEN b.estado = 'Completado' AND b.espera_min BETWEEN 0 AND 480
         THEN 1 ELSE 0 END                                                     AS espera_valida,
    CASE WHEN b.estado = 'Completado' AND b.atencion_min BETWEEN 0 AND 480
         THEN 1 ELSE 0 END                                                     AS atencion_valida,
    CASE WHEN b.estado = 'Completado' AND b.espera_min BETWEEN 0 AND 10
         THEN 1 ELSE 0 END                                                     AS dentro_sla,   -- SLA = SUM(dentro_sla) / SUM(espera_valida)
    CURRENT_TIMESTAMP()                                                        AS fecha_actualizacion
FROM base b
