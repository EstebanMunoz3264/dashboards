-- =====================================================================
-- DASHBOARD GESTIÓN AGENCIAS · FCR POR CICLOS (réplica exacta del modelo corporativo)
-- Tabla en Power BI: dash_agencias_fcr (consulta nativa)
-- Réplica del notebook 91_Ingesta_FCR (celdas 15-20) que genera dwh_prod.db_gold.fcr_ciclos:
--   * Catálogo de soluciones elegibles = el mismo que usa fcr_ciclos (sale del Excel
--     Listado Elegibilidad FCR.xlsx); se lee de la propia tabla fcr_ciclos, así se
--     actualiza solo cuando cambia el Excel.
--   * Contacto   = cada fila de crm_interacciones con solución elegible (sin quitar duplicados)
--   * Fecha      = FECHA_CIERRE
--   * Ciclo      = misma CUENTA + misma SOLUCIÓN, contactos separados por <= 72 h
--   * Fila final = ciclo x ESPECIFICO x CIUDAD (igual que fcr_ciclos)
--   * Exitoso    = 1 solo contacto y la solución del primer contacto es FCR Sí
--   * Evaluable  = ya pasaron 72 h desde el inicio del ciclo (hora Ecuador)
-- Se agrega: asesor, agencia, tipología y problema del primer contacto (no existen en fcr_ciclos)
-- Alcance: ciclos cuyo primer contacto fue en Agencia / Retencionestelco / Centro de Experiencia, desde 2026
-- =====================================================================
WITH catalogo AS (
    SELECT SOLUCION_KEY                       AS solucion_key,
           MAX(first_contact_fcr_si_no)       AS fcr_si_no
    FROM dwh_prod.db_gold.fcr_ciclos
    GROUP BY SOLUCION_KEY
),
base AS (
    SELECT
        i.ID,
        i.ACCOUNT_ID,
        i.ESPECIFICO,
        i.CIUDAD,
        i.PROBLEMA,
        i.SERVICIO_TIPO,
        i.AGENCIA,
        i.USUARIO,
        COALESCE(i.CANAL, '(NO_DEFINIDO)')                                         AS canal_fcr,
        TO_TIMESTAMP(i.FECHA_CIERRE)                                               AS fecha_contacto,
        -- misma normalización de la solución que el notebook (celda 9)
        COALESCE(NULLIF(TRIM(
            TRIM(REGEXP_REPLACE(REGEXP_REPLACE(UPPER(TRANSLATE(
                COALESCE(NULLIF(TRIM(i.SOLUCION), ''), '(NULL)'),
                'ÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÑ', 'AEIOUAEIOUAEIOUN')),
                '[^A-Z0-9 ]', ' '), ' +', ' '))
        ), ''), '(NULL)')                                                           AS solucion_key
    FROM dwh_prod.db_gold.crm_interacciones i
    WHERE i.ACCOUNT_ID IS NOT NULL
      AND i.FECHA_CREACION IS NOT NULL
      AND i.FECHA_CREACION >= '2025-12-01'          -- margen para no cortar ciclos de inicio de enero
),
elegibles AS (
    SELECT b.*, c.fcr_si_no
    FROM base b
    JOIN catalogo c ON c.solucion_key = b.solucion_key
),
ord AS (
    SELECT *,
           LAG(fecha_contacto) OVER (PARTITION BY ACCOUNT_ID, solucion_key ORDER BY fecha_contacto, ID) AS prev_fecha
    FROM elegibles
),
marks AS (
    SELECT *,
           CASE WHEN prev_fecha IS NULL THEN 1
                WHEN UNIX_TIMESTAMP(fecha_contacto) - UNIX_TIMESTAMP(prev_fecha) > 72 * 3600 THEN 1
                ELSE 0 END                                                         AS new_cycle_flag
    FROM ord
),
seq AS (
    SELECT *,
           SUM(new_cycle_flag) OVER (PARTITION BY ACCOUNT_ID, solucion_key ORDER BY fecha_contacto, ID
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cycle_seq
    FROM marks
),
ciclos AS (
    SELECT
        ACCOUNT_ID,
        solucion_key,
        ESPECIFICO,
        CIUDAD,
        cycle_seq,
        MIN(fecha_contacto)                                                        AS fecha_inicio_ciclo,
        MAX(fecha_contacto)                                                        AS fecha_ultimo_contacto,
        COUNT(*)                                                                   AS num_contactos,
        MIN_BY(fcr_si_no, fecha_contacto)                                          AS first_contact_fcr_si_no,
        MAX_BY(fcr_si_no, fecha_contacto)                                          AS last_contact_fcr_si_no,
        MIN_BY(canal_fcr, fecha_contacto)                                          AS canal,
        MIN_BY(ID, fecha_contacto)                                                 AS id_primer_contacto,
        MIN_BY(AGENCIA, fecha_contacto)                                            AS agencia,
        MIN_BY(USUARIO, fecha_contacto)                                            AS usuario,
        MIN_BY(SERVICIO_TIPO, fecha_contacto)                                      AS tipologia,
        MIN_BY(PROBLEMA, fecha_contacto)                                           AS problema
    FROM seq
    GROUP BY ACCOUNT_ID, solucion_key, cycle_seq, ESPECIFICO, CIUDAD
)
SELECT
    TRIM(CAST(c.ACCOUNT_ID AS STRING))                                             AS Cuenta,
    UPPER(TRIM(REGEXP_REPLACE(COALESCE(c.ESPECIFICO, ''), '[\\r\\n]+', '')))      AS Motivo,
    c.cycle_seq                                                                    AS n_ciclo,
    c.id_primer_contacto,
    c.fecha_inicio_ciclo,
    c.fecha_ultimo_contacto,
    c.num_contactos                                                                AS contactos_ciclo,
    c.canal                                                                        AS Canal,
    TRIM(c.agencia)                                                                AS agencia,
    CASE WHEN LOWER(TRIM(c.usuario)) LIKE 'telco\\_%' ESCAPE '\\'
         THEN LOWER(TRIM(c.usuario))
         ELSE CONCAT('telco_', LOWER(TRIM(c.usuario))) END                         AS Asesor,
    TRIM(c.tipologia)                                                              AS Tipologia,
    UPPER(TRIM(REGEXP_REPLACE(c.problema, '[\\r\\n]+', '')))                       AS Problema,
    c.solucion_key                                                                 AS solucion_primer_contacto,
    c.solucion_key                                                                 AS solucion_ultimo_contacto,
    DATE(c.fecha_inicio_ciclo)                                                     AS Fecha,
    CAST(DATE_TRUNC('MONTH', c.fecha_inicio_ciclo) AS DATE)                        AS Mes,
    CASE WHEN c.num_contactos > 1 THEN 1 ELSE 0 END                                AS con_recontacto,
    1                                                                              AS elegible,
    CASE WHEN c.first_contact_fcr_si_no = 'FCR Si' THEN 1 ELSE 0 END               AS fcr_si,
    1                                                                              AS elegible_ult,
    CASE WHEN c.last_contact_fcr_si_no = 'FCR Si' THEN 1 ELSE 0 END                AS fcr_si_ult,
    CASE WHEN FROM_UTC_TIMESTAMP(CURRENT_TIMESTAMP(), 'America/Guayaquil')
              >= c.fecha_inicio_ciclo + INTERVAL 72 HOURS THEN 1 ELSE 0 END        AS ciclo_evaluable,
    CURRENT_TIMESTAMP()                                                            AS fecha_actualizacion
FROM ciclos c
WHERE c.canal IN ('Agencia', 'Retencionestelco', 'Centro de Experiencia')
  AND c.fecha_inicio_ciclo >= '2026-01-01'
