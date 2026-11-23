-- =====================================================================
-- DASHBOARD GESTIÓN AGENCIAS · SATISFACCIÓN DEL CLIENTE (CSAT)
-- Tabla en Power BI: dash_satisfaccion_cliente (consulta nativa)
-- Fuente: dwh_prod.db_gold.satisfaccion_cliente (encuestas SURVEYUP / CHATBOT, escala 1 a 5)
-- Mismo universo y cálculo que el Tablero General de Indicadores (Histórico Satisfacción):
--   * Canales_Principal_transaccion = 'Agencia' (Canal_Final Agencia y Retenciones)
--   * La tabla origen acumula un corte por cada ejecución (execution_date) sin borrar el anterior:
--     se toma solo la última ejecución de cada mes para no contar dos veces la misma encuesta
--   * % Satisfacción = SUM(CSAT_flag_satisfecho) / SUM(CSAT_valido_flag)
--   * Satisfacción ponderada = % satisfacción de cada flujo (año, mes, etapa del journey,
--     subtipo de evento) ponderado por TRANSACCIONES_FINALES del flujo
-- Agencia y asesor (vienen en la tabla origen, notebook Satisfaccion_nuevo):
--   * Asesor  = usuario de la última llamada CRM antes de la encuesta (columna usuario)
--               (validado nov-2026: 100% igual al cruce propio con dom_cliente_eventos)
--   * Agencia = crm_agencias de esa llamada; cuando viene vacía o NO APLICA:
--               Canal_Final = 'Retenciones' -> 'Retención' (equipo de retención)
--               resto -> agencia donde el asesor registra más interacciones en el CRM
-- =====================================================================
WITH enc AS (
    SELECT s.*
    FROM dwh_prod.db_gold.satisfaccion_cliente s
    WHERE s.Canales_Principal_transaccion = 'Agencia'
      AND s.anio >= 2026
    QUALIFY s.execution_date = MAX(s.execution_date) OVER (PARTITION BY s.anio, s.mes)
),
agencia_principal AS (
    -- Agencia donde el asesor registra más interacciones (solo para completar NO APLICA)
    SELECT zz_usuario, zz_agencia
    FROM (
        SELECT REGEXP_REPLACE(LOWER(TRIM(ci.USUARIO)), '^telco_', '') AS zz_usuario,
               TRIM(ci.AGENCIA)                                      AS zz_agencia,
               COUNT(*)                                              AS n
        FROM dwh_prod.db_gold.crm_interacciones ci
        WHERE ci.CANAL IN ('Agencia', 'Retencionestelco', 'Centro de Experiencia')
          AND ci.FECHA_CREACION >= '2026-01-01'
          AND NULLIF(TRIM(ci.AGENCIA), '') IS NOT NULL
          AND UPPER(TRIM(ci.AGENCIA)) <> 'NO APLICA'
        GROUP BY 1, 2
    )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY zz_usuario ORDER BY n DESC, zz_agencia) = 1
)
SELECT
    CONCAT_WS('|', s.enc_fuente, s.id_fuente_natural, s.ACCOUNT_ID, s.enc_fecha_envio) AS id_encuesta_key,
    s.ID_ENCUESTA,
    s.id_fuente_natural,
    s.enc_fuente                                                           AS fuente,
    TRIM(CAST(s.ACCOUNT_ID AS STRING))                                     AS Cuenta,
    s.enc_fecha_envio,
    s.fecha_evento,
    s.execution_date                                                       AS fecha_carga,
    CASE WHEN YEAR(s.enc_fecha_envio) = s.anio AND MONTH(s.enc_fecha_envio) = s.mes
         THEN DATE(s.enc_fecha_envio) ELSE MAKE_DATE(s.anio, s.mes, 1) END        AS Fecha,
    MAKE_DATE(s.anio, s.mes, 1)                                            AS Mes,
    s.anio,
    s.mes                                                                  AS mes_num,
    s.Canal_Final                                                          AS canal_final,
    s.Canales_Principal_transaccion                                        AS canal_principal,
    s.etapas_Jorney                                                        AS etapa_journey,
    s.subtipo_evento,
    s.voc_survey_name                                                      AS encuesta,
    s.enc_region_principal                                                 AS region,
    s.enc_tecnologia_acceso                                                AS tecnologia,
    s.CSAT_score                                                           AS csat_score,
    s.enc_grupo_csat                                                       AS grupo_csat,
    s.CSAT_valido_flag                                                     AS csat_valido,
    s.CSAT_flag_satisfecho                                                 AS csat_satisfecho,
    s.CSAT_flag_neutro                                                     AS csat_neutro,
    s.CSAT_flag_insatisfecho                                               AS csat_insatisfecho,
    s.TRANSACCIONES_FINALES                                                AS transacciones_finales,
    s.comentario,
    CASE WHEN NULLIF(TRIM(s.usuario), '') IS NULL THEN NULL
         ELSE CONCAT('telco_', REGEXP_REPLACE(LOWER(TRIM(s.usuario)), '^telco_', '')) END AS Asesor,
    CASE WHEN NULLIF(TRIM(s.crm_agencias), '') IS NOT NULL
          AND UPPER(TRIM(s.crm_agencias)) <> 'NO APLICA'      THEN TRIM(s.crm_agencias)
         WHEN s.Canal_Final = 'Retenciones'                    THEN 'Retención'
         ELSE ap.zz_agencia END                                            AS agencia,
    CASE WHEN NULLIF(TRIM(s.crm_agencias), '') IS NOT NULL
          AND UPPER(TRIM(s.crm_agencias)) <> 'NO APLICA'      THEN 'Llamada'
         WHEN s.Canal_Final = 'Retenciones'                    THEN 'Equipo Retenciones'
         WHEN ap.zz_agencia IS NOT NULL                        THEN 'Principal del asesor'
         ELSE 'Sin agencia' END                                            AS origen_agencia,
    CURRENT_TIMESTAMP()                                                    AS fecha_actualizacion
FROM enc s
LEFT JOIN agencia_principal ap
  ON ap.zz_usuario = REGEXP_REPLACE(LOWER(TRIM(s.usuario)), '^telco_', '')
