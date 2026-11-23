-- =====================================================================
-- BASE DASHBOARD FLUJOS DE DESERCIÓN - Internet Residencial
-- Grano: 1 fila por CITEM_ID dado de baja, desde julio 2026
-- Uso: consulta nativa desde Power BI (sin CREATE TABLE, sin ';' final)
-- =====================================================================
--CREATE OR REPLACE TABLE dwh_prod.db_tmp.base_flujos_desercion AS
WITH 
-- Bajas únicas por cuenta + fecha de baja (llave para todas las ventanas)
bajas_fecha AS (
    SELECT DISTINCT
        ACCOUNT_ID,
        FECHA_PROCESO_RAIZ_BAJA
    FROM dwh_prod.db_gold.flujos_desercion
    WHERE NEGOCIO IN ('Internet Residencial')
      AND FECHA_PROCESO_RAIZ_BAJA >= '2026-07-01'
),
-- Fecha mínima a leer (6 meses antes de la baja más antigua), solo para acotar lectura
rango AS (
    SELECT ADD_MONTHS(MIN(DATE(FECHA_PROCESO_RAIZ_BAJA)), -6) AS fecha_desde
    FROM bajas_fecha
),
-- Interacciones CRM en la ventana, SIN las de deserción
crm_base AS (
    SELECT
        CI.ACCOUNT_ID,
        CI.CALL_LOG_ID,
        CI.FECHA_CREACION,
        UPPER(TRIM(REGEXP_REPLACE(CI.ESPECIFICO, '[\\r\\n]+', '')))       AS especifico_norm
    FROM dwh_prod.db_gold.crm_interacciones CI
    WHERE DATE(CI.FECHA_CREACION) >= (SELECT fecha_desde FROM rango)
      AND NOT (
               COALESCE(UPPER(TRIM(REGEXP_REPLACE(CI.PROBLEMA, '[\\r\\n]+', ''))), '') = 'DESERCIONES'
            OR (    COALESCE(UPPER(TRIM(REGEXP_REPLACE(CI.PROBLEMA,   '[\\r\\n]+', ''))), '') = 'PROCESOS ADMINISTRATIVOS'
                AND COALESCE(UPPER(TRIM(REGEXP_REPLACE(CI.ESPECIFICO, '[\\r\\n]+', ''))), '') = 'INFO. DESERCIÓN')
            OR COALESCE(UPPER(TRIM(CI.SERVICIO_TIPO)), '') = 'DESERCIONES'
            OR COALESCE(UPPER(TRIM(REGEXP_REPLACE(CI.ESPECIFICO, '[\\r\\n]+', ''))), '') = 'DESERCIONES'
      )
),
-- Clasificación del específico (no excluyente): técnico / facturación / traslado
crm_sin_desercion AS (
    SELECT
        c.*,
        CASE WHEN c.especifico_norm RLIKE
                  '\\bLED|WIFI LENTA|INTERMITENTE|SIN SERVICIO \\(MTA|INCIDENCIA EN SECTOR|NO ENCIENDE|FUERA DE RANGO|SEÑAL WIFI EN|PÁGINAS|VISITA TÉCNICA REPETIDA|PUERTO DE CABLE|ROUTER|NAP\\b|SIN SEÑAL|MTA / ONT TIENE|ANCHO DE BANDA|SATURACIÓN|RED INTERNA|NO RESPONDE'
             THEN 1 ELSE 0 END                                             AS es_tecnico,
        CASE WHEN c.especifico_norm RLIKE
                  'SALDOS|COBRO|FACTURACI|DESCUENTO NO APLICADO|PROMOCIÓN NO OTORGADA|FACTURAR SIN|FINALIZA BENEFICIO|DEVOLUCIÓN DE VALORES'
             THEN 1 ELSE 0 END                                             AS es_facturacion,
        CASE WHEN c.especifico_norm RLIKE
                  'CAMBIO DE DIRECCIÓN|CAMBIO DE CIUDAD'
             THEN 1 ELSE 0 END                                             AS es_traslado
    FROM crm_base c
),
visitas AS (
    SELECT
        b.ACCOUNT_ID,
        b.FECHA_PROCESO_RAIZ_BAJA,
        COUNT(DISTINCT FSM.IPROCESS_ID)                                    AS visitas_tecnicas_6m,
        COUNT(DISTINCT CASE WHEN DATE(FL.ENDDATE) >= DATE_SUB(DATE(b.FECHA_PROCESO_RAIZ_BAJA), 30)
                            THEN FSM.IPROCESS_ID END)                      AS visitas_tecnicas_30d,
        MAX(DATE(FL.ENDDATE))                                              AS fecha_ultima_visita,
        CONCAT_WS(' | ', COLLECT_SET(UPPER(TRIM(FSM.MOTIVOS_REAL))))       AS motivos_visitas_concat
    FROM dwh_prod.db_gold.flujos FL
    JOIN dwh_prod.db_gold.FSM FSM
        ON FL.IPROCESS_ID = FSM.IPROCESS_ID
    JOIN bajas_fecha b
        ON  TRY_CAST(FL.ACCOUNT_ID AS DECIMAL(38,0)) = b.ACCOUNT_ID
        AND DATE(FL.ENDDATE) >= ADD_MONTHS(DATE(b.FECHA_PROCESO_RAIZ_BAJA), -6)
        AND FL.ENDDATE <= b.FECHA_PROCESO_RAIZ_BAJA
    WHERE FL.ESTADO_FLUJO = 'FINALIZADO'
      AND FL.NOPROCESS ILIKE '%VIS%'
      AND DATE(FL.ENDDATE) >= (SELECT fecha_desde FROM rango)
      AND (
            UPPER(FSM.MOTIVOS_REAL) IN (
                'ANTIDESERCION',
                'CAMBIO DE ROUTER EN MAL ESTADO',
                'OPE / CAMBIAR ACCESORIO DE INTERNET EN MAL ESTADO / PROBLEMA DE NAVEGACION',
                'OPE / CAMBIAR EQUIPO DE INTERNET EN MAL ESTADO / PROBLEMA DE NAVEGACION',
                'OPE / CAMBIAR ROUTER EN MAL ESTADO / PROBLEMA CON WIFI',
                'OPE / CAMBIO DE MATERIAL EN MAL ESTADO / PROBLEMA DE NAVEGACION',
                'OPE / CAMBIO DE MATERIAL MANIPULADO O DAÑADO POR EL CLIENTE / PROBLEMA DE NAVEGACIÓN',
                'OPE / CONFIGURAR ROUTER POR PROBLEMAS TECNICOS / PROBLEMA CON WIFI',
                'OPE / RECONEXIÓN / SIN SERVICIO',
                'OPE / RESETEAR EQUIPOS DE INTERNET INHIBIDO / EQUIPO INHIBIDO',
                'OPE/CAMBIAR ACCESORIO DE INTERNET EN MAL ESTADO/PROBLEMA DE NAVEGACION',
                'OPE/CAMBIAR EQUIPO DE INTERNET EN MAL ESTADO/PROBLEMA DE NAVEGACION',
                'RESETEAR EQUIPOS DE INTERNET INHIBIDO'
            )
            OR UPPER(FSM.MOTIVOS_REAL) LIKE '%ANTIDESERCION%'
            OR UPPER(FSM.MOTIVOS_REAL) LIKE '%CAMBIO DE MATERIAL (INT)%'
            OR UPPER(FSM.MOTIVOS_REAL) LIKE '%MODEM NO ENGANCHA (INT)%'
      )
    GROUP BY b.ACCOUNT_ID, b.FECHA_PROCESO_RAIZ_BAJA
),
llamadas AS (
    SELECT
        b.ACCOUNT_ID,
        b.FECHA_PROCESO_RAIZ_BAJA,
        COUNT(DISTINCT CI.CALL_LOG_ID)                                     AS llamadas_tecnicas_6m,
        COUNT(DISTINCT CASE WHEN DATE(CI.FECHA_CREACION) >= DATE_SUB(DATE(b.FECHA_PROCESO_RAIZ_BAJA), 30)
                            THEN CI.CALL_LOG_ID END)                       AS llamadas_tecnicas_30d,
        MAX(DATE(CI.FECHA_CREACION))                                       AS fecha_ultima_llamada_tecnica,
        CONCAT_WS(' | ', COLLECT_SET(CI.especifico_norm))                  AS motivos_llamadas_concat
    FROM crm_sin_desercion CI
    JOIN bajas_fecha b
        ON  TRY_CAST(CI.ACCOUNT_ID AS DECIMAL(38,0)) = b.ACCOUNT_ID
        AND DATE(CI.FECHA_CREACION) >= ADD_MONTHS(DATE(b.FECHA_PROCESO_RAIZ_BAJA), -6)
        AND CI.FECHA_CREACION <= b.FECHA_PROCESO_RAIZ_BAJA
    WHERE CI.es_tecnico = 1
    GROUP BY b.ACCOUNT_ID, b.FECHA_PROCESO_RAIZ_BAJA
),
interacciones AS (
    SELECT
        b.ACCOUNT_ID,
        b.FECHA_PROCESO_RAIZ_BAJA,
        COUNT(DISTINCT CI.CALL_LOG_ID)                                     AS interacciones_6m,
        COUNT(DISTINCT CASE WHEN DATE(CI.FECHA_CREACION) >= DATE_SUB(DATE(b.FECHA_PROCESO_RAIZ_BAJA), 30)
                            THEN CI.CALL_LOG_ID END)                       AS interacciones_30d,
        MAX(DATE(CI.FECHA_CREACION))                                       AS fecha_ultima_interaccion,
        COUNT(DISTINCT CASE WHEN CI.es_facturacion = 1 THEN CI.CALL_LOG_ID END) AS contactos_facturacion_6m,
        COUNT(DISTINCT CASE WHEN CI.es_traslado    = 1 THEN CI.CALL_LOG_ID END) AS contactos_traslado_6m,
        CONCAT_WS(' | ', COLLECT_SET(CI.especifico_norm))                  AS motivos_interacciones_concat
    FROM crm_sin_desercion CI
    JOIN bajas_fecha b
        ON  TRY_CAST(CI.ACCOUNT_ID AS DECIMAL(38,0)) = b.ACCOUNT_ID
        AND DATE(CI.FECHA_CREACION) >= ADD_MONTHS(DATE(b.FECHA_PROCESO_RAIZ_BAJA), -6)
        AND CI.FECHA_CREACION <= b.FECHA_PROCESO_RAIZ_BAJA
    GROUP BY b.ACCOUNT_ID, b.FECHA_PROCESO_RAIZ_BAJA
),
-- =====================================================================
-- (1) PASO POR RETENCIÓN
-- =====================================================================
-- Tickets de retención en los 6 meses previos a la baja (sin rechazados)
tickets_ventana AS (
    SELECT
        b.ACCOUNT_ID,
        b.FECHA_PROCESO_RAIZ_BAJA,
        DATE(t.Fecha_Llamada)                                              AS fecha_ticket,
        t.Retencion,
        UPPER(TRIM(t.Retencion))                                           AS retencion_norm,
        NULLIF(UPPER(TRIM(REGEXP_REPLACE(t.Motivo_Real, '[\\r\\n]+', ''))), '') AS motivo_retencion,
        CASE WHEN t.Departamento = 'Agencia' THEN 'Agencia'
             ELSE 'CallCenter' END                                         AS canal_retencion
    FROM dwh_prod.db_gold.tickets_deserciones t
    JOIN bajas_fecha b
        ON  TRY_CAST(t.Cuenta AS DECIMAL(38,0)) = b.ACCOUNT_ID
        AND DATE(t.Fecha_Llamada) >= ADD_MONTHS(DATE(b.FECHA_PROCESO_RAIZ_BAJA), -6)
        AND DATE(t.Fecha_Llamada) <= DATE(b.FECHA_PROCESO_RAIZ_BAJA)
    WHERE DATE(t.Fecha_Llamada) >= (SELECT fecha_desde FROM rango)
      AND t.Retencion     IN ('SI', 'SI CRM', 'NO')
      AND t.Departamento  IN ('Agencia', 'Call Center', 'CallCenter', 'ServicioMail', '360')
      AND COALESCE(t.estado_ticket, '') NOT IN ('Rechazado', 'Ticket rechazado')
),
-- Último ticket en los 90 días previos a la baja (el que gestionó esta baja)
ticket_ultimo AS (
    SELECT
        ACCOUNT_ID,
        FECHA_PROCESO_RAIZ_BAJA,
        fecha_ticket,
        Retencion,
        canal_retencion,
        motivo_retencion
    FROM tickets_ventana
    WHERE fecha_ticket >= DATE_SUB(DATE(FECHA_PROCESO_RAIZ_BAJA), 90)
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ACCOUNT_ID, FECHA_PROCESO_RAIZ_BAJA
        ORDER BY fecha_ticket DESC
    ) = 1
),
-- Historial de tickets 6 meses: cuántos y si fue retenido antes
tickets_resumen AS (
    SELECT
        ACCOUNT_ID,
        FECHA_PROCESO_RAIZ_BAJA,
        COUNT(*)                                                           AS n_tickets_retencion_6m,
        SUM(CASE WHEN retencion_norm IN ('SI', 'SI CRM') THEN 1 ELSE 0 END) AS n_retenciones_si_6m,
        MAX(CASE WHEN retencion_norm IN ('SI', 'SI CRM') THEN fecha_ticket END) AS fecha_ultima_retencion_si,
        CONCAT_WS(' | ', COLLECT_SET(motivo_retencion))                    AS motivos_retencion_6m,
        CONCAT_WS(' | ', COLLECT_SET(CASE WHEN retencion_norm IN ('SI', 'SI CRM')
                                          THEN motivo_retencion END))      AS motivos_retenido_si_6m
    FROM tickets_ventana
    GROUP BY ACCOUNT_ID, FECHA_PROCESO_RAIZ_BAJA
),
-- =====================================================================
-- (3) FACTURACIÓN INTERNET RESIDENCIAL: facturas emitidas hasta la
--     fecha de baja, últimos 3 meses (mes de baja, -1 y -2)
-- =====================================================================
facturas_lineas AS (
    SELECT
        b.ACCOUNT_ID,
        b.FECHA_PROCESO_RAIZ_BAJA,
        CAST(DATE_TRUNC('MONTH', fa.FECHA_CREACION) AS DATE)               AS mes_fact,
        fa.NOMBRE_RUBRO,
        fa.NETINITAMOUNT,
        fa.TAXAMOUNT,
        fa.INITAMOUNT,
        fa.FECHA_CREACION,
        CASE WHEN UPPER(COALESCE(fa.ELEMENTDEF, '')) LIKE '%DESCUENTO%'
               OR UPPER(COALESCE(fa.ELEMENTDEF, '')) LIKE '%DISCOUNT%'
               OR UPPER(COALESCE(fa.ELEMENTDEF, '')) LIKE '%PROMOCIONES%'
             THEN 1 ELSE 0 END                                             AS es_descuento
    FROM dwh_prod.db_gold.facturacion fa
    JOIN bajas_fecha b
        ON  TRY_CAST(fa.CPARTYACCOUNT_ID AS DECIMAL(38,0)) = b.ACCOUNT_ID
        AND fa.FECHA_CREACION >= ADD_MONTHS(TRUNC(DATE(b.FECHA_PROCESO_RAIZ_BAJA), 'MM'), -2)
        AND fa.FECHA_CREACION <= b.FECHA_PROCESO_RAIZ_BAJA
    WHERE fa.SISTEMA             = 'TYTAN'
      AND fa.VALIDO              = 'TRUE'
      AND fa.ANULADO             = 'NO ANULADO'
      AND fa.CLASIFICACION       = 'MENSUALIDAD'
      AND fa.TIPO_DOCF           = 'Factura'
      AND fa.SEGMENTO_FINANCIERO = 'Internet Residencial'
      AND (fa.NOMBRE_RUBRO IS NULL OR fa.NOMBRE_RUBRO NOT LIKE '%REVISTA%')
      AND DATE_TRUNC('MONTH', fa.FECHA_CREACION) = DATE_TRUNC('MONTH', NVL(fa.DFROM, fa.FECHA_CREACION))
      AND fa.FECHA_CREACION >= (SELECT ADD_MONTHS(TRUNC(MIN(DATE(FECHA_PROCESO_RAIZ_BAJA)), 'MM'), -2) FROM bajas_fecha)
),
-- Línea del servicio principal: 1 por cuenta/baja/mes
facturas_principal AS (
    SELECT
        ACCOUNT_ID,
        FECHA_PROCESO_RAIZ_BAJA,
        mes_fact,
        NETINITAMOUNT,
        TAXAMOUNT,
        INITAMOUNT
    FROM facturas_lineas
    WHERE es_descuento = 0
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ACCOUNT_ID, FECHA_PROCESO_RAIZ_BAJA, mes_fact
        ORDER BY
            CASE
                WHEN NOMBRE_RUBRO = 'SERVICIO PRINCIPAL' THEN 0
                WHEN NOMBRE_RUBRO = 'Servicio Internet'  THEN 1
                ELSE 2
            END,
            NETINITAMOUNT DESC,
            FECHA_CREACION DESC
    ) = 1
),
-- ARPU 3m + última/primera factura del servicio principal
arpu AS (
    SELECT
        p.ACCOUNT_ID,
        p.FECHA_PROCESO_RAIZ_BAJA,
        COUNT(*)                                                           AS meses_facturados_3m,
        ROUND(AVG(p.NETINITAMOUNT), 2)                                     AS arpu_neto_3m,
        ROUND(AVG(p.INITAMOUNT), 2)                                        AS arpu_imp_3m,
        MAX(p.mes_fact)                                                    AS mes_ultima_factura,
        ROUND(MAX_BY(p.NETINITAMOUNT, p.mes_fact), 2)                      AS ultima_factura_neta,
        ROUND(MAX_BY(p.TAXAMOUNT,     p.mes_fact), 2)                      AS ultima_factura_impuesto,
        ROUND(MAX_BY(p.INITAMOUNT,    p.mes_fact), 2)                      AS ultima_factura_imp,
        MIN(p.mes_fact)                                                    AS mes_primera_factura,
        ROUND(MIN_BY(p.NETINITAMOUNT, p.mes_fact), 2)                      AS primera_factura_neta
    FROM facturas_principal p
    GROUP BY p.ACCOUNT_ID, p.FECHA_PROCESO_RAIZ_BAJA
),
migracion AS (
    SELECT 
        ACCOUNT_ID,
        SEGMENTO_GPON
    FROM dwh_prod.db_gold.cuentas_migracion
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ACCOUNT_ID
        ORDER BY ACCOUNT_ID
    ) = 1
),
-- =====================================================================
-- (4) PERFIL DEL CLIENTE (dwpbase deduplicado por cuenta)
-- =====================================================================
dwpunico AS (
    SELECT
        ACCOUNT_ID,
        PRODUCTO,
        MESES_EDAD_CLI_CUET,
        EDAD_CLIENTE,
        PROVINCIA,
        SECTOR,
        SUBSECTOR,
        canalDeVenta,
        VARIANTE_PRODUCTO,
        FECHA_ACTIVACION,
        VEL_DOWN,
        SPEED,
        NODO_HFC_GPON,
        COD_NODO,
        NOM_NODO,
        TECNOLOGIA_ACCESO
    FROM dwh_prod.db_gold.dwpbase
    WHERE TRY_CAST(ACCOUNT_ID AS DECIMAL(38,0)) IN (SELECT ACCOUNT_ID FROM bajas_fecha)
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ACCOUNT_ID
        ORDER BY
            CASE WHEN ESTADO_PRODUCTO = 'ACTIVO' THEN 0 ELSE 1 END ASC,
            CASE WHEN PRODUCTO = 'Internet'   THEN 0
                 WHEN PRODUCTO = 'Television' THEN 1
                 ELSE 2 END ASC,
            FECHA_MAX_TERMINACION DESC
    ) = 1
),
-- Usabilidad ANTES de la baja: último corte del mes anterior a la baja;
-- si no existe, el corte del mes -2. Si no hay ninguno, queda null.
-- Ej.: baja 2026-09-14 -> corte ago-2026 (si no hay, jul-2026)
usabilidad AS (
    SELECT 
        b.ACCOUNT_ID,
        b.FECHA_PROCESO_RAIZ_BAJA,
        uc.FECHA_CORTE AS fecha_corte_usabilidad,
        CASE MONTHS_BETWEEN(TRUNC(DATE(b.FECHA_PROCESO_RAIZ_BAJA), 'MM'), TRUNC(uc.FECHA_CORTE, 'MM'))
             WHEN 1 THEN 'Mes -1'
             WHEN 2 THEN 'Mes -2'
        END                                                                AS origen_corte_usabilidad,
        uc.SegmentoUsoDown,
        uc.EstadoEquipo,
        uc.PromedioConsumoDown30,
        uc.TotalConsumoDown30,
        uc.DiasConsumo,
        uc.UsoReciente
    FROM bajas_fecha b
    JOIN dwh_prod.db_gold.usabilidad_cuentas uc
        ON  TRY_CAST(uc.ACCOUNT_ID AS DECIMAL(38,0)) = b.ACCOUNT_ID
        AND uc.FECHA_CORTE <  TRUNC(DATE(b.FECHA_PROCESO_RAIZ_BAJA), 'MM')
        AND uc.FECHA_CORTE >= ADD_MONTHS(TRUNC(DATE(b.FECHA_PROCESO_RAIZ_BAJA), 'MM'), -2)
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY b.ACCOUNT_ID, b.FECHA_PROCESO_RAIZ_BAJA
        ORDER BY uc.FECHA_CORTE DESC
    ) = 1
),
-- =====================================================================
-- (2) SEÑALES DE CAMBIO: caída de uso ANTES de la baja
--     Corte actual = corte de usabilidad (mes -1, o mes -2)
--     Referencia   = corte 2 meses antes del corte actual
--     Ej.: baja 2026-09-14 -> actual = ago-2026, referencia = jun-2026
-- =====================================================================
usabilidad_ref AS (
    SELECT
        u.ACCOUNT_ID,
        u.FECHA_PROCESO_RAIZ_BAJA,
        uc.FECHA_CORTE                                                     AS fecha_corte_ref,
        uc.SegmentoUsoDown                                                 AS SegmentoUsoDown_ref,
        uc.PromedioConsumoDown30                                           AS PromedioConsumoDown30_ref,
        uc.DiasConsumo                                                     AS DiasConsumo_ref
    FROM usabilidad u
    JOIN dwh_prod.db_gold.usabilidad_cuentas uc
        ON  TRY_CAST(uc.ACCOUNT_ID AS DECIMAL(38,0)) = u.ACCOUNT_ID
        AND TRUNC(uc.FECHA_CORTE, 'MM') = ADD_MONTHS(TRUNC(u.fecha_corte_usabilidad, 'MM'), -2)
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY u.ACCOUNT_ID, u.FECHA_PROCESO_RAIZ_BAJA
        ORDER BY uc.FECHA_CORTE DESC
    ) = 1
),
-- =====================================================================
-- BASE: todas las columnas anteriores (mismo resultado de la versión previa)
-- =====================================================================
base AS (
    select
            f.*,
            v.visitas_tecnicas_6m,
            v.motivos_visitas_concat,
            l.llamadas_tecnicas_6m,
            l.motivos_llamadas_concat,
            i.interacciones_6m,
            i.motivos_interacciones_concat,
            COALESCE(i.contactos_facturacion_6m, 0)                            AS contactos_facturacion_6m,
            COALESCE(i.contactos_traslado_6m, 0)                               AS contactos_traslado_6m,
            m.SEGMENTO_GPON,
            u.fecha_corte_usabilidad,
            u.origen_corte_usabilidad,
            u.SegmentoUsoDown,
            u.EstadoEquipo,
            u.PromedioConsumoDown30,
            u.TotalConsumoDown30,
            u.DiasConsumo,
            u.UsoReciente,

            -- ===== (1) PASO POR RETENCIÓN =====
            CASE WHEN tu.ACCOUNT_ID IS NOT NULL THEN 1 ELSE 0 END              AS tuvo_ticket_retencion,
            COALESCE(tu.Retencion, 'Sin ticket retención')                     AS resultado_retencion,
            tu.canal_retencion,
            COALESCE(tu.motivo_retencion, CASE WHEN tu.ACCOUNT_ID IS NOT NULL THEN 'Sin motivo registrado' END) AS motivo_ultimo_ticket_retencion,
            NULLIF(tr.motivos_retencion_6m, '')                                AS motivos_retencion_6m,
            NULLIF(tr.motivos_retenido_si_6m, '')                              AS motivos_retenido_si_6m,
            tu.fecha_ticket                                                    AS fecha_ultimo_ticket,
            COALESCE(tr.n_tickets_retencion_6m, 0)                             AS n_tickets_retencion_6m,
            COALESCE(tr.n_retenciones_si_6m, 0)                                AS n_retenciones_si_6m,
            CASE WHEN COALESCE(tr.n_retenciones_si_6m, 0) > 0 THEN 1 ELSE 0 END AS retenido_previamente,
            tr.fecha_ultima_retencion_si,
            DATEDIFF(DATE(f.FECHA_PROCESO_RAIZ_BAJA), tr.fecha_ultima_retencion_si) AS dias_retencion_si_a_baja,

            -- ===== (2) SEÑALES DE CAMBIO =====
            -- Caída de uso previa a la baja (corte usabilidad vs corte 2 meses antes)
            ur.fecha_corte_ref                                                 AS fecha_corte_usabilidad_ref,
            ur.SegmentoUsoDown_ref,
            ur.PromedioConsumoDown30_ref,
            CASE WHEN ur.PromedioConsumoDown30_ref > 0 AND u.PromedioConsumoDown30 >= 0
                 THEN ROUND((u.PromedioConsumoDown30 - ur.PromedioConsumoDown30_ref)
                            / ur.PromedioConsumoDown30_ref * 100, 2)
            END                                                                AS var_pct_consumo_down30,
            CASE WHEN ur.DiasConsumo_ref >= 0 AND u.DiasConsumo >= 0
                 THEN u.DiasConsumo - ur.DiasConsumo_ref
            END                                                                AS var_dias_consumo,
            CASE WHEN ur.PromedioConsumoDown30_ref > 0 AND u.PromedioConsumoDown30 >= 0
                  AND (u.PromedioConsumoDown30 - ur.PromedioConsumoDown30_ref)
                      / ur.PromedioConsumoDown30_ref <= -0.30
                 THEN 1 ELSE 0 END                                             AS caida_uso_fuerte,
            v.visitas_tecnicas_30d,
            l.llamadas_tecnicas_30d,
            i.interacciones_30d,
            DATEDIFF(DATE(f.FECHA_PROCESO_RAIZ_BAJA), v.fecha_ultima_visita)           AS dias_ultima_visita_a_baja,
            DATEDIFF(DATE(f.FECHA_PROCESO_RAIZ_BAJA), l.fecha_ultima_llamada_tecnica)  AS dias_ultima_llamada_tecnica_a_baja,
            DATEDIFF(DATE(f.FECHA_PROCESO_RAIZ_BAJA), i.fecha_ultima_interaccion)      AS dias_ultima_interaccion_a_baja,
            CASE WHEN COALESCE(v.visitas_tecnicas_6m, 0) >= 2
                   OR COALESCE(l.llamadas_tecnicas_6m, 0) >= 3
                 THEN 1 ELSE 0 END                                             AS reincidencia_tecnica,

            -- ===== (3) FACTURACIÓN INTERNET RESIDENCIAL (servicio principal) =====
            a.meses_facturados_3m,
            a.arpu_neto_3m,
            a.arpu_imp_3m,
            a.mes_ultima_factura,
            a.ultima_factura_neta,
            a.ultima_factura_impuesto,
            a.ultima_factura_imp,
            a.mes_primera_factura,
            a.primera_factura_neta,
            CASE WHEN a.primera_factura_neta > 0 AND a.mes_ultima_factura > a.mes_primera_factura
                 THEN ROUND((a.ultima_factura_neta - a.primera_factura_neta) / a.primera_factura_neta * 100, 2)
            END                                                                AS var_pct_factura,
            CASE WHEN a.primera_factura_neta > 0 AND a.mes_ultima_factura > a.mes_primera_factura
                  AND (a.ultima_factura_neta - a.primera_factura_neta) / a.primera_factura_neta >= 0.10
                 THEN 1 ELSE 0 END                                             AS aumento_factura,

            -- ===== (4) PERFIL DEL CLIENTE =====
            d.PRODUCTO,
            d.MESES_EDAD_CLI_CUET,
            d.EDAD_CLIENTE,
            d.PROVINCIA,
            d.SECTOR                                                           AS dwp_SECTOR,
            d.SUBSECTOR                                                        AS dwp_SUBSECTOR,
            d.canalDeVenta,
            d.VARIANTE_PRODUCTO,
            d.FECHA_ACTIVACION,
            CASE WHEN DATE(d.FECHA_ACTIVACION) <= DATE(f.FECHA_PROCESO_RAIZ_BAJA)
                 THEN FLOOR(MONTHS_BETWEEN(DATE(f.FECHA_PROCESO_RAIZ_BAJA), DATE(d.FECHA_ACTIVACION)))
            END                                                                AS meses_antiguedad_a_baja,
            d.VEL_DOWN,
            d.SPEED,
            CASE WHEN d.PRODUCTO = 'Internet' 
                 THEN dwh_prod.db_parameters.udf_process_speed(d.SPEED, d.SPEED).VELOCIDAD_CONTRATADA 
                 ELSE NULL END                                                 AS megas_contratadas,
            CASE WHEN d.PRODUCTO = 'Internet' 
                 THEN dwh_prod.db_parameters.udf_process_speed(d.SPEED, d.SPEED).VELOCIDAD_RECIBIDA 
                 ELSE NULL END                                                 AS megas_recibidas,
            d.NODO_HFC_GPON,
            d.COD_NODO                                                         AS dwp_COD_NODO,
            d.NOM_NODO,
            d.TECNOLOGIA_ACCESO

    from dwh_prod.db_gold.flujos_desercion f
    left join visitas v 
           on v.ACCOUNT_ID = f.ACCOUNT_ID
          and v.FECHA_PROCESO_RAIZ_BAJA = f.FECHA_PROCESO_RAIZ_BAJA
    left join llamadas l 
           on l.ACCOUNT_ID = f.ACCOUNT_ID
          and l.FECHA_PROCESO_RAIZ_BAJA = f.FECHA_PROCESO_RAIZ_BAJA
    left join interacciones i 
           on i.ACCOUNT_ID = f.ACCOUNT_ID
          and i.FECHA_PROCESO_RAIZ_BAJA = f.FECHA_PROCESO_RAIZ_BAJA
    left join migracion m on TRY_CAST(m.ACCOUNT_ID AS DECIMAL(38,0)) = f.ACCOUNT_ID
    left join dwpunico d on TRY_CAST(d.ACCOUNT_ID AS DECIMAL(38,0)) = f.ACCOUNT_ID
    left join usabilidad u 
           on u.ACCOUNT_ID = f.ACCOUNT_ID
          and u.FECHA_PROCESO_RAIZ_BAJA = f.FECHA_PROCESO_RAIZ_BAJA
    left join usabilidad_ref ur 
           on ur.ACCOUNT_ID = f.ACCOUNT_ID
          and ur.FECHA_PROCESO_RAIZ_BAJA = f.FECHA_PROCESO_RAIZ_BAJA
    left join ticket_ultimo tu 
           on tu.ACCOUNT_ID = f.ACCOUNT_ID
          and tu.FECHA_PROCESO_RAIZ_BAJA = f.FECHA_PROCESO_RAIZ_BAJA
    left join tickets_resumen tr 
           on tr.ACCOUNT_ID = f.ACCOUNT_ID
          and tr.FECHA_PROCESO_RAIZ_BAJA = f.FECHA_PROCESO_RAIZ_BAJA
    left join arpu a 
           on a.ACCOUNT_ID = f.ACCOUNT_ID
          and a.FECHA_PROCESO_RAIZ_BAJA = f.FECHA_PROCESO_RAIZ_BAJA
    where f.NEGOCIO IN('Internet Residencial') --('Televisión', 'Telefonía')) 
    and f.FECHA_PROCESO_RAIZ_BAJA >= '2026-07-01'
    -- 1 fila por CITEM_ID (flujos_desercion trae algunos repetidos con distinto MES_TERMINACION)
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY f.CITEM_ID
        ORDER BY f.MES_TERMINACION DESC NULLS LAST, f.FECHA_TERMINACION DESC NULLS LAST
    ) = 1
),
-- =====================================================================
-- (6) MOTIVO CONSOLIDADO (lo que el cliente declaró)
-- =====================================================================
base_motivo AS (
    SELECT
        base.*,
        CASE
            WHEN UPPER(TRIM(MOTIVO_TERMINACION)) IN (
                    'NUEVO DOMICILIO YA CUENTA CON EL SERVICIO',
                    'CAMBIO DE DOMICILIO A ZONA SIN COBERTURA',
                    'MUDANZA A ZONA SIN COBERTURA',
                    'CAMBIO DE CIUDAD / VIAJE',
                    'SALIDA DEL PAÍS')
                THEN 'Mudanza / Domicilio'
            WHEN UPPER(TRIM(MOTIVO_TERMINACION)) IN (
                    'INTERMITENCIA DE SEÑAL',
                    'VISITA TÉCNICA NO RESUELVE',
                    'VISITA TÉCNICA NO LLEGÓ',
                    'FALTA DE COBERTURA WIFI',
                    'CAÍDA DEL NODO',
                    'INCONFORMIDAD CON DISPONIBILIDAD DE VT')
                THEN 'Técnico / Calidad'
            WHEN UPPER(TRIM(MOTIVO_TERMINACION)) IN (
                    'CAMBIO A LA COMPETENCIA POR SERVICIO',
                    'CAMBIO A LA COMPETENCIA POR PRECIO / BENEFICIOS',
                    'SE CAMBIA A LA COMPETENCIA')
                THEN 'Competencia'
            WHEN UPPER(TRIM(MOTIVO_TERMINACION)) IN (
                    'INCONFORMIDAD CON PRECIO / PLAN',
                    'COSTO DE CAMBIO DE DOMICILIO',
                    'FINALIZA BENEFICIO PROMOCIONAL',
                    'FACTURACIÓN POR RECONEXIÓN',
                    'FACTURACIÓN SERVICIO NO SOLICITADO',
                    'INCONFORMIDAD BENEFICIOS CONADIS/TERCERA EDAD')
                THEN 'Precio / Facturación'
            WHEN UPPER(TRIM(MOTIVO_TERMINACION)) IN (
                    'SITUACIÓN ECONÓMICA',
                    'CANCELACION POR NO PAGO DE FACTURA (MORA)')
                THEN 'Económico'
            WHEN UPPER(TRIM(MOTIVO_TERMINACION)) IN (
                    'YA NO USA EL SERVICIO')
                THEN 'Bajo uso'
            WHEN UPPER(TRIM(MOTIVO_TERMINACION)) LIKE '%ZONA PELIGROSA%'
              OR UPPER(TRIM(MOTIVO_TERMINACION)) IN ('EXTORSIÓN/VACUNAS')
                THEN 'Seguridad / Zona peligrosa'
            WHEN UPPER(TRIM(MOTIVO_TERMINACION)) IN (
                    'CIERRE DE NEGOCIO',
                    'CLIENTE FALLECIDO',
                    'PROBLEMAS DE SALUD',
                    'CLIENTE TERCERA EDAD',
                    'MOTIVOS PERSONALES')
                THEN 'Situación personal'
            WHEN UPPER(TRIM(MOTIVO_TERMINACION)) IN (
                    'MALA VENTA',
                    'VENTA CARRUSEL',
                    'MIGRACIÓN INTERNET',
                    'MIGRACIÓN TV',
                    'MIGRACIÓN A TV BOX (SIN OVERLAY)',
                    'NO ACEPTA MIGRACIÓN CAMBIO DE TECNOLOGIA',
                    'NO ACEPTA MIGRACIÓN (TV/OVERLAY)',
                    'CAMBIO EN ZAPPING',
                    'MODIFICACIONES EN GRILLA DE CANALES',
                    'EXTENSIÓN DE METRAJE')
                THEN 'Comercial / Producto'
            WHEN MOTIVO_TERMINACION IS NULL
              OR UPPER(TRIM(MOTIVO_TERMINACION)) IN ('NO DA INFORMACIÓN')
                THEN 'Sin información'
            ELSE 'Otros'
        END                                                                AS motivo_raiz
    FROM base
)
SELECT
    base_motivo.*,
    -- ===== CLASIFICACIONES =====
    CASE
        WHEN motivo_raiz IN ('Técnico / Calidad', 'Competencia', 'Precio / Facturación',
                             'Bajo uso', 'Comercial / Producto')          THEN 'Controlable'
        WHEN motivo_raiz IN ('Mudanza / Domicilio', 'Económico',
                             'Seguridad / Zona peligrosa', 'Situación personal') THEN 'No controlable'
        ELSE 'Sin información'
    END                                                                    AS tipo_motivo,
    CAST(DATE_TRUNC('MONTH', FECHA_PROCESO_RAIZ_BAJA) AS DATE)           AS mes_baja,
    CASE WHEN SEGMENTO_GPON IN ('FIBRA NATIVO', 'MIGRADOS') THEN SEGMENTO_GPON
         ELSE 'Sin proyecto HFC' END                                       AS segmento_gpon_grupo,
    CASE WHEN meses_antiguedad_a_baja IS NULL THEN 'Sin dato'
         WHEN meses_antiguedad_a_baja <  6    THEN '1. 0-6'
         WHEN meses_antiguedad_a_baja < 12    THEN '2. 6-12'
         WHEN meses_antiguedad_a_baja < 24    THEN '3. 12-24'
         WHEN meses_antiguedad_a_baja < 36    THEN '4. 24-36'
         WHEN meses_antiguedad_a_baja < 60    THEN '5. 36-60'
         ELSE '6. 60+' END                                           AS rango_antiguedad,
    CASE WHEN arpu_neto_3m IS NULL THEN 'Sin facturación'
         WHEN arpu_neto_3m < 15    THEN '1. < $15'
         WHEN arpu_neto_3m < 20    THEN '2. $15-20'
         WHEN arpu_neto_3m < 25    THEN '3. $20-25'
         WHEN arpu_neto_3m < 30    THEN '4. $25-30'
         ELSE '5. >= $30' END                                              AS rango_arpu,
    CASE WHEN megas_contratadas IS NULL THEN 'Sin dato'
         WHEN megas_contratadas <= 100  THEN '1. <= 100'
         WHEN megas_contratadas <= 300  THEN '2. 101-300'
         WHEN megas_contratadas <= 500  THEN '3. 301-500'
         ELSE '4. > 500' END                                          AS rango_megas,
    -- ===== BANDERAS DE SEÑALES PREVIAS (6 meses) =====
    CASE WHEN COALESCE(llamadas_tecnicas_6m, 0) > 0 THEN 1 ELSE 0 END      AS contacto_tecnico_6m,
    CASE WHEN contactos_facturacion_6m > 0 THEN 1 ELSE 0 END               AS contacto_facturacion_6m,
    CASE WHEN contactos_traslado_6m > 0 THEN 1 ELSE 0 END                  AS contacto_traslado_6m,
    CASE WHEN COALESCE(visitas_tecnicas_6m, 0) > 0 THEN 1 ELSE 0 END       AS visita_tecnica_6m,
    CASE WHEN COALESCE(llamadas_tecnicas_6m, 0) > 0
           OR COALESCE(visitas_tecnicas_6m, 0) > 0
           OR contactos_facturacion_6m > 0
           OR aumento_factura = 1
         THEN 1 ELSE 0 END                                                 AS con_alguna_senal,
    -- Lo que mostraban los datos antes de la baja (prioridad en este orden)
    CASE
        WHEN reincidencia_tecnica = 1                         THEN '1. Técnica (reincidencia)'
        WHEN aumento_factura = 1                              THEN '2. Precio (aumento de factura)'
        WHEN caida_uso_fuerte = 1                             THEN '3. Caída de uso'
        ELSE '4. Sin señal'
    END                                                                    AS senal_principal
FROM base_motivo
