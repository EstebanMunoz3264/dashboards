-- =====================================================================
-- INTERACCIONES PREVIAS AL FLUJO - Internet Residencial
-- Grano: 1 fila por flujo (CITEM_ID) e interacción CRM (CALL_LOG_ID)
-- Ventana: los 30 días anteriores a la fecha del flujo (sin incluir el día del flujo)
-- Incluye TODAS las interacciones CRM: técnicas, no técnicas y de deserción
-- motivo_comentario: motivo real leído del comentario del asesor (solo interacciones de deserción, por reglas)
-- motivo_real_flujo: motivo real más repetido en los comentarios de deserción del flujo
-- Uso: consulta nativa desde Power BI (sin ';' final)
-- =====================================================================
WITH
flujos_base AS (
    SELECT DISTINCT
        CITEM_ID,
        ACCOUNT_ID,
        DATE(FECHA_PROCESO_RAIZ_BAJA)                                       AS fecha_flujo
    FROM dwh_prod.db_gold.flujos_desercion
    WHERE NEGOCIO IN ('Internet Residencial')
      AND FECHA_PROCESO_RAIZ_BAJA >= '2026-07-01'
),
rango AS (
    SELECT DATE_SUB(MIN(fecha_flujo), 31) AS fecha_desde
    FROM flujos_base
),
crm AS (
    SELECT
        TRY_CAST(CI.ACCOUNT_ID AS DECIMAL(38,0))                            AS ACCOUNT_ID,
        CI.CALL_LOG_ID,
        CI.FECHA_CREACION,
        DATE(CI.FECHA_CREACION)                                             AS fecha_interaccion,
        CI.CANAL,
        UPPER(TRIM(REGEXP_REPLACE(CI.SERVICIO_TIPO, '[\\r\\n]+', '')))      AS servicio_tipo_norm,
        UPPER(TRIM(REGEXP_REPLACE(CI.PROBLEMA,      '[\\r\\n]+', '')))      AS problema_norm,
        UPPER(TRIM(REGEXP_REPLACE(CI.ESPECIFICO,    '[\\r\\n]+', '')))      AS especifico_norm,
        TRIM(REGEXP_REPLACE(COALESCE(CI.COMENTARIO, ''), '[\\r\\n\\t]+', ' ')) AS comentario
    FROM dwh_prod.db_gold.crm_interacciones CI
    WHERE DATE(CI.FECHA_CREACION) >= (SELECT fecha_desde FROM rango)
),
base AS (
    SELECT
        f.CITEM_ID,
        f.ACCOUNT_ID,
        f.fecha_flujo,
        c.CALL_LOG_ID,
        c.FECHA_CREACION                                                    AS fecha_hora_interaccion,
        c.fecha_interaccion,
        DATEDIFF(f.fecha_flujo, c.fecha_interaccion)                        AS dias_antes_flujo,
        CASE WHEN c.fecha_interaccion >= TRUNC(f.fecha_flujo, 'MM') THEN 1 ELSE 0 END AS en_mes_del_flujo,
        c.CANAL                                                             AS canal_interaccion,
        c.servicio_tipo_norm                                                AS servicio_tipo,
        c.problema_norm                                                     AS problema,
        c.especifico_norm                                                   AS motivo_interaccion,
        CASE
            WHEN COALESCE(c.problema_norm, '') = 'DESERCIONES'
              OR (COALESCE(c.problema_norm, '') = 'PROCESOS ADMINISTRATIVOS' AND COALESCE(c.especifico_norm, '') = 'INFO. DESERCIÓN')
              OR COALESCE(c.servicio_tipo_norm, '') = 'DESERCIONES'
              OR COALESCE(c.especifico_norm, '') = 'DESERCIONES'
                THEN 'Deserción'
            WHEN c.especifico_norm RLIKE
                 '\\bLED|WIFI LENTA|INTERMITENTE|SIN SERVICIO \\(MTA|INCIDENCIA EN SECTOR|NO ENCIENDE|FUERA DE RANGO|SEÑAL WIFI EN|PÁGINAS|VISITA TÉCNICA REPETIDA|PUERTO DE CABLE|ROUTER|NAP\\b|SIN SEÑAL|MTA / ONT TIENE|ANCHO DE BANDA|SATURACIÓN|RED INTERNA|NO RESPONDE'
                THEN 'Técnica'
            ELSE 'No técnica'
        END                                                                 AS tipo_interaccion,
        SUBSTR(c.comentario, 1, 400)                                        AS comentario,
        CASE
            WHEN TRIM(COALESCE(c.comentario,'')) = '' THEN 'Sin comentario'
            WHEN UPPER(TRANSLATE(COALESCE(c.comentario,''),'áéíóúÁÉÍÓÚñÑüÜ','aeiouAEIOUnNuU')) RLIKE '(SIN COBERTURA|NO HAY COBERTURA|NO TIENE COBERTURA|NO EXISTE COBERTURA|FUERA DE COBERTURA|NO HAY FACTIBILIDAD|SIN FACTIBILIDAD|NO (ESTA EN|HAY|TIENE) (ZONA DE )?COB|NO HAY FIBRA|FALTA DE COBERTURA|POR COBERTURA|REFLEJA COBERTURA|NO (SE )?MANTIENE RED|NO TIENEN .{0,20}EN ESA ZONA|EXCEDENTE DE .{0,10}METROS|ZONA SIN|SIN RED|NO HAY RED|NO LLEGA (LA )?RED|ZONA RURAL|FINCA|HACIENDA)' THEN 'Cambio de domicilio - zona sin cobertura'
            WHEN UPPER(TRANSLATE(COALESCE(c.comentario,''),'áéíóúÁÉÍÓÚñÑüÜ','aeiouAEIOUnNuU')) RLIKE '(CDD|\\bCDC\\b|CAMDIR|CAMBIO DE DIR|CAMBIO DE D[IO]M|CAMBIAR(A)? DE? (DOM|DIR|CASA)|MUD(O|A|AR|ARA|ANZA)\\b|NUEVO DOMICILIO|NUEVA DIRECCION|DONDE RESIDIRA|SE CAMBI).{0,120}(YA (LE |LES )?(BRINDAN|TIENE|TIENEN|CUENTA|CUENTAN|MANTIENE|MANTIENEN|HAY|DAN)|OTRA OPERADORA|YA EXISTE|OTRA LINEA)|NUEVO DOMICILIO YA CUENTA' THEN 'Cambio de domicilio - ya tiene servicio en el nuevo domicilio'
            WHEN UPPER(TRANSLATE(COALESCE(c.comentario,''),'áéíóúÁÉÍÓÚñÑüÜ','aeiouAEIOUnNuU')) RLIKE '(VIAJ|\\bPAIS\\b|\\bPAI\\b|EXTERIOR|EXTRANJERO|ESPANA|EEUU|ESTADOS UNIDOS|EUROPA|CAMBI[A-Z]* DE CIUDAD|PROVINCIA|PROBICIA|SAL[A-Z]* DE LA CIUDAD|MEJOR TRABAJO|MOTIVOS? DE TRABAJO|POR SU TRABAJO|NO PASA EN EL DOMICILIO|TRASLAD[A-Z]* A LA CIUDAD|PASE PARA|SALIDA DE (LA )?CIUDAD|OTRA CIUDAD|OTRA PROVINCIA|(SE IRA|SE VA|SE MUDA|SE MUDARA) (DE|A) (LA |OTRA )?(CIUDAD|PROVINCIA)|SE VA A VIVIR|MIGRA|BOLETO)' THEN 'Viaje / sale del país o de la ciudad'
            WHEN UPPER(TRANSLATE(COALESCE(c.comentario,''),'áéíóúÁÉÍÓÚñÑüÜ','aeiouAEIOUnNuU')) RLIKE '(SIN SERVICIO|SIN SERV\\b|SIN INTERNET|SIN INT\\b|NO TIENE (INTERNET|INT\\b|SERVICIO|SENAL)|INTERMITEN|LENTITUD|\\bLENT[OA]\\b|FALLA|SE CAE|CAIDA|CORTES|NO FUNCIONA|NO NAVEGA|MALA SENAL|SIN SENAL|NO RESOLVIERON|NO HAN RESUELTO|NO LE RESUELVEN|INCONVENIENTES|AVERIA|PROB[A-Z]* (TECNICOS|CON EL SERV|DE SERV|DE SENAL|DE CONEXION|DE INTERNET|CON EL INTERNET)|MAL SERVICIO|PESIMO SERVICIO|NO INSTALARON|NO REALIZARON LA INSTALACION|TECNICOS NO|PROB[A-Z]* (CON |EN |DE |DEL )(LA |EL )?(SENAL|INT|SERV|SRV|PLAN|CONEXION|RED|INTERNET|WIFI)|PROBLEMAS CONSTANTES|PROBLEMAS RECURRENTE|INCONFORMIDAD (CON|DEL|POR) (EL |LA )?(SERV|CALIDAD|INTERNET)|MAL SERV|SERVICIO (SUPER |MUY )?MALO|NO LE DAN SOLUCION|SIN SOLUCION|NO SE ARREGLA|NO SE LE PUDO INSTALAR|CONDUCTOS|CABLEADO|CABLES|NO PUEDEN ACCEDER|PROBLEMA PERSIS|CONTINUA EL PROBLEMA|PESE A (LA )?VT|POR (MUCHOS )?PROBLEMAS\\b|PORBELMAS|PROBELMAS|MALA EXPE|MAS VELOCIDAD|ZONA ROJA|PELIGROS|NO PUEDEN (LOS )?TEC|MALA EXPERIENCIA)' THEN 'Problemas técnicos / sin servicio'
            WHEN UPPER(TRANSLATE(COALESCE(c.comentario,''),'áéíóúÁÉÍÓÚñÑüÜ','aeiouAEIOUnNuU')) RLIKE '(COMPETENCIA|COPETEN|CONTRATO UN NUEVO|NUEVO PROVEEDOR|PROPIO OPERADOR|OFRECIENDO OTROS SERV|CAMBIO DE (OPERADORA|PROVEEDOR|OPERADOR)|CAMBIAR(A)? DE (OPERADORA|PROVEEDOR)|OTRA OPR|OTRA EMPRESA|OTRO PROVEEDOR|OTRA OPERADORA|OTRO OPERADOR|NETLIFE|\\bCNT\\b|\\bCLARO\\b|MOVISTAR|PUNTONET|CELERITY|FIBRAMAX|TELCONET|MEJOR (OFERTA|PLAN|PRECIO)|MAS BARATO|PROMOCION DE OTRA|YA (TIENE|CONTRATO|CUENTA CON) OTRO (SERV|PROVEEDOR|INTERNET)|OTRO SERV(ICIO)? DE INT|YA TIENE OTRO SERV)' THEN 'Competencia / mejor oferta'
            WHEN UPPER(TRANSLATE(COALESCE(c.comentario,''),'áéíóúÁÉÍÓÚñÑüÜ','aeiouAEIOUnNuU')) RLIKE '((POR|DEBIDO A(L)?|MOTIVO( DE)?|X|PARA) (UN |EL |LA )?(CDD|CAMDIR|CAMBIO DE (DIR|DOM|CASA|VIVIENDA))|CAMBIAR(A)? DE? (DOM|DIR|CASA)|\\bCDC\\b|SE CAMBIO DE (DIR|DOM|CASA)|SE FUE A VIVIR|YA NO HABITA|INQUILINO|(?<!OFRECE )(?<!OFERTA )(?<!OFRECIO )(?<!INDICA )(?<!BRINDA )CAMBIO DE (CASA|DIRECCION|DIR|D[IO]MICILIO|VIVIENDA)|SE CDD|NO VIVE (EN|AHI)|SE TRASLA|MUD(O|A|AR|ARA|ANZA)\\b|YA NO (ESTA VIVIENDO|VIVE|RESIDE)|OTRO DOMICILIO|OTRA VIVIENDA|ENTREGA (LA CASA|EL DEPARTAMENTO|EL DPTO|LA VIVIENDA)|DEJA (LA CASA|EL DEPARTAMENTO|EL DPTO)|ARRIEND|ALQUIL|SE CAMBIA DE (CASA|DOMICILIO|DEPARTAMENTO|DPTO)|SOLICITA (LA )?CANC[A-Z]* (POR|X) CDD|CDD (A|SIN|DONDE|YA))' THEN 'Cambio de domicilio - otro'
            WHEN UPPER(TRANSLATE(COALESCE(c.comentario,''),'áéíóúÁÉÍÓÚñÑüÜ','aeiouAEIOUnNuU')) RLIKE '(ECONO|PRECIO|VALORES ALTOS|PAGA MUCHO|CANCELA MUCHO|PLAN MENOR|ELEVAD|POR (EL )?(COSTO|VALOR)\\b|TEMAS? (DE )?VALORES|NO PUEDE CUBRIR|NO PUEDE PAGAR|NO PODRA PAGAR|SIN TRABAJO|SIN EMPLEO|DESEMPLE|SE QUEDO SIN|NO TIENE (DINERO|PARA PAGAR|RECURSOS)|FALTA DE (DINERO|RECURSOS)|COSTO ALTO|MUY CARO|ELEVADO|ALTO COSTO|\\bCARO\\b|REDUCIR GASTOS|NO LE ALCANZA)' THEN 'Económico / no puede pagar'
            WHEN UPPER(TRANSLATE(COALESCE(c.comentario,''),'áéíóúÁÉÍÓÚñÑüÜ','aeiouAEIOUnNuU')) RLIKE '(CERRO (EL |SU )?(NEGOCIO|LOCAL|LUGAR)|YA NO ESTARA EN EL LOCAL|PIDIERON EL LOCAL|CIERRE DE(L)? (NEGOCIO|LOCAL|EMPRESA|OFICINA)|CIERRA (EL |SU )?(NEGOCIO|LOCAL)|CERRAR (EL |SU )?(NEGOCIO|LOCAL)|ENTREGA(R)? (EL )?LOCAL|LOCAL COMERCIAL|QUIEBRA)' THEN 'Cierre de negocio / local'
            WHEN UPPER(TRANSLATE(COALESCE(c.comentario,''),'áéíóúÁÉÍÓÚñÑüÜ','aeiouAEIOUnNuU')) RLIKE '(NO (LO )?USA\\b|YA NO USAN|NO LO NECE?SITA|PAGANDO .{0,15}EN VANO|SE MANTIENE SOLO|TIENE (DOS|2) SERV|YA NO (LO )?(ESTA USANDO|VA A USAR|USARA)|NO (LO )?UTILIZA|NO ESTA (USANDO|UTILIZANDO)|YA NO (LO )?(NECESITA|REQUIERE|OCUPA)|NO LO NECESITA|POCO USO|NO HAY QUIEN|NADIE (LO )?USA|NO TIENE CON QUIEN|CASA SOLA|PAGANDO POR ALGO QUE NO)' THEN 'Ya no usa / no lo necesita'
            WHEN UPPER(TRANSLATE(COALESCE(c.comentario,''),'áéíóúÁÉÍÓÚñÑüÜ','aeiouAEIOUnNuU')) RLIKE '(FALLEC|DIFUNT|\\bMURIO\\b|DEFUNCION|\\bSALUD\\b|ENFERM|HOSPITAL)' THEN 'Fallecimiento / salud'
            WHEN UPPER(TRANSLATE(COALESCE(c.comentario,''),'áéíóúÁÉÍÓÚñÑüÜ','aeiouAEIOUnNuU')) RLIKE '(MALA ATENCION|MALA VENTA|ENGAN|NO LE INFORMARON|COBRO(S)? (INDEBIDO|EXCESIVO|DE MAS)|COBRAN DE MAS|NO RECIBE LO CONTRATADO|NO CUMPLIERON|INCUMPL|INCONFORM|FRANJA|SERIEDAD|\\bTRATO\\b|CARRUSEL|NO LE (HAN )?PERMITID|INSATISFECH|ARCOTEL|DENUNCI|DEFENSORIA|LEY ORGANICA)' THEN 'Mala atención / venta / facturación'
            WHEN UPPER(TRANSLATE(COALESCE(c.comentario,''),'áéíóúÁÉÍÓÚñÑüÜ','aeiouAEIOUnNuU')) RLIKE '(NO (DA|BRINDA|INDICA|MENCIONA|ESPECIFICA)( UN| EL)? (MOTIVO|INF|RAZON)|NO DESEA (DAR|BRINDAR|INDICAR|MENCIONAR)( UN| EL)? (MOTIVO|INF|RAZON)|MOTIVOS? PERSONAL|CUESTIONES PERSONALES|INDOLE PERSONAL|NO DA MAS (DETALLE|APERTURA|INF)|NO DESEA DAR (MAYOR|MAS)|SIN MOTIVO|NO ESPECIFICA)' THEN 'No da motivo / personal'
            ELSE 'Sin motivo identificable (solo trámite)'
        END                                                               AS motivo_comentario_all
    FROM flujos_base f
    JOIN crm c
        ON  c.ACCOUNT_ID = f.ACCOUNT_ID
        AND c.fecha_interaccion >= DATE_SUB(f.fecha_flujo, 30)
        AND c.fecha_interaccion <  f.fecha_flujo
),
marcado AS (
    SELECT *,
        CASE WHEN tipo_interaccion = 'Deserción' THEN motivo_comentario_all END AS motivo_comentario
    FROM base
),
motivo_flujo AS (
    SELECT CITEM_ID, motivo_comentario AS motivo_real_flujo
    FROM (
        SELECT CITEM_ID, motivo_comentario,
               ROW_NUMBER() OVER (PARTITION BY CITEM_ID
                                  ORDER BY CASE WHEN motivo_comentario IN ('Sin motivo identificable (solo trámite)', 'Sin comentario') THEN 1 ELSE 0 END,
                                           COUNT(*) DESC, MAX(fecha_hora_interaccion) DESC) AS rn
        FROM marcado
        WHERE motivo_comentario IS NOT NULL
        GROUP BY CITEM_ID, motivo_comentario
    ) x
    WHERE rn = 1
)
SELECT
    m.CITEM_ID, m.ACCOUNT_ID, m.fecha_flujo, m.CALL_LOG_ID, m.fecha_hora_interaccion, m.fecha_interaccion,
    m.dias_antes_flujo, m.en_mes_del_flujo, m.canal_interaccion, m.servicio_tipo, m.problema,
    m.motivo_interaccion, m.tipo_interaccion, m.comentario, m.motivo_comentario,
    CASE WHEN mf.motivo_real_flujo = 'Sin comentario' THEN 'Sin motivo identificable (solo trámite)' ELSE mf.motivo_real_flujo END AS motivo_real_flujo
FROM marcado m
LEFT JOIN motivo_flujo mf ON mf.CITEM_ID = m.CITEM_ID
