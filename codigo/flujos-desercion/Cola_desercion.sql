-- =====================================================================
-- COLA DE BAJA - Internet (cuentas con contacto de deserción desde el 24 del mes anterior hasta hoy)
-- Grano: 1 fila por cuenta (ACCOUNT_ID)
-- estado_cola: Generó flujo / Revocó la cancelación / Retenido / En cola - no retenido / En cola - sin gestión de retención
-- Uso: consulta nativa desde Power BI (sin ';' final)
-- =====================================================================
WITH
crm AS (
    SELECT
        TRY_CAST(CI.ACCOUNT_ID AS DECIMAL(38,0))                            AS ACCOUNT_ID,
        CI.CALL_LOG_ID,
        CI.FECHA_CREACION,
        DATE(CI.FECHA_CREACION)                                             AS fecha_interaccion,
        CI.CANAL,
        CI.AGENCIA,
        CI.CIUDAD,
        CI.NOMBRE_CUENTA,
        CI.TELEFONO,
        TRIM(CI.TIPO_NEGOCIO)                                               AS tipo_negocio,
        CI.tecnologia_acceso,
        UPPER(TRIM(REGEXP_REPLACE(CI.SERVICIO_TIPO, '[\\r\\n]+', '')))      AS servicio_tipo_norm,
        UPPER(TRIM(REGEXP_REPLACE(CI.PROBLEMA,      '[\\r\\n]+', '')))      AS problema_norm,
        UPPER(TRIM(REGEXP_REPLACE(CI.ESPECIFICO,    '[\\r\\n]+', '')))      AS especifico_norm,
        TRIM(REGEXP_REPLACE(COALESCE(CI.COMENTARIO, ''), '[\\r\\n\\t]+', ' ')) AS comentario
    FROM dwh_prod.db_gold.crm_interacciones CI
    WHERE DATE(CI.FECHA_CREACION) >= DATE_ADD(TRUNC(ADD_MONTHS(CURRENT_DATE(), -1), 'MM'), 23)   -- desde el 24 del mes anterior (último corte)
      AND TRIM(CI.TIPO_NEGOCIO) LIKE '%Int%'
),
des AS (
    SELECT c.*,
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
        END AS motivo_comentario
    FROM crm c
    WHERE COALESCE(c.problema_norm, '') = 'DESERCIONES'
       OR (COALESCE(c.problema_norm, '') = 'PROCESOS ADMINISTRATIVOS' AND COALESCE(c.especifico_norm, '') = 'INFO. DESERCIÓN')
       OR COALESCE(c.servicio_tipo_norm, '') = 'DESERCIONES'
       OR COALESCE(c.especifico_norm, '') = 'DESERCIONES'
),
cuenta AS (
    SELECT ACCOUNT_ID,
           MIN(fecha_interaccion) AS primer_contacto,
           MAX(fecha_interaccion) AS ultimo_contacto,
           COUNT(*)               AS n_contactos_desercion
    FROM des GROUP BY ACCOUNT_ID
),
ultimo AS (
    SELECT * FROM (
        SELECT d.*, ROW_NUMBER() OVER (PARTITION BY ACCOUNT_ID ORDER BY FECHA_CREACION DESC) AS rn
        FROM des d
    ) z WHERE rn = 1
),
motivo AS (
    SELECT ACCOUNT_ID, motivo_comentario AS motivo_real
    FROM (
        SELECT ACCOUNT_ID, motivo_comentario,
               ROW_NUMBER() OVER (PARTITION BY ACCOUNT_ID
                                  ORDER BY CASE WHEN motivo_comentario IN ('Sin motivo identificable (solo trámite)', 'Sin comentario') THEN 1 ELSE 0 END,
                                           COUNT(*) DESC, MAX(FECHA_CREACION) DESC) AS rn
        FROM des GROUP BY ACCOUNT_ID, motivo_comentario
    ) x WHERE rn = 1
),
flujo AS (
    SELECT cu.ACCOUNT_ID, MIN(DATE(f.FECHA_PROCESO_RAIZ_BAJA)) AS fecha_flujo, MAX(f.NEGOCIO) AS negocio_flujo
    FROM cuenta cu
    JOIN dwh_prod.db_gold.flujos_desercion f
      ON TRY_CAST(f.ACCOUNT_ID AS DECIMAL(38,0)) = cu.ACCOUNT_ID
     AND DATE(f.FECHA_PROCESO_RAIZ_BAJA) >= cu.primer_contacto
    GROUP BY cu.ACCOUNT_ID
),
ticket AS (
    SELECT cu.ACCOUNT_ID,
           MAX(CASE WHEN t.Retencion IN ('SI', 'SI CRM') THEN 1 ELSE 0 END) AS retenido_ticket,
           MAX(CASE WHEN t.Retencion = 'NO' THEN 1 ELSE 0 END)              AS no_retenido_ticket,
           MAX(DATE(t.Fecha_Llamada))                                       AS fecha_ultimo_ticket
    FROM cuenta cu
    JOIN dwh_prod.db_gold.tickets_deserciones t
      ON TRY_CAST(t.Cuenta AS DECIMAL(38,0)) = cu.ACCOUNT_ID
     AND DATE(t.Fecha_Llamada) >= cu.primer_contacto
    WHERE t.Retencion IN ('SI', 'SI CRM', 'NO')
      AND t.Departamento IN ('Agencia', 'Call Center', 'CallCenter', 'ServicioMail', '360')
    GROUP BY cu.ACCOUNT_ID
)
SELECT
    cu.ACCOUNT_ID,
    u.NOMBRE_CUENTA                                         AS nombre_cuenta,
    u.TELEFONO                                              AS telefono,
    u.CIUDAD                                                AS ciudad,
    u.tipo_negocio,
    u.tecnologia_acceso,
    cu.primer_contacto,
    cu.ultimo_contacto,
    cu.n_contactos_desercion,
    DATEDIFF(CURRENT_DATE(), cu.primer_contacto)            AS dias_desde_primer_contacto,
    DATEDIFF(CURRENT_DATE(), cu.ultimo_contacto)            AS dias_desde_ultimo_contacto,
    u.especifico_norm                                       AS ultimo_motivo_crm,
    u.CANAL                                                 AS ultimo_canal,
    u.AGENCIA                                               AS ultima_agencia,
    SUBSTR(u.comentario, 1, 400)                            AS ultimo_comentario,
    CASE WHEN m.motivo_real = 'Sin comentario' THEN 'Sin motivo identificable (solo trámite)' ELSE m.motivo_real END AS motivo_real,
    fl.fecha_flujo,
    fl.negocio_flujo,
    DATEDIFF(fl.fecha_flujo, cu.primer_contacto)            AS dias_hasta_flujo,
    COALESCE(tk.retenido_ticket, 0)                         AS retenido_ticket,
    COALESCE(tk.no_retenido_ticket, 0)                      AS no_retenido_ticket,
    CASE
        WHEN fl.fecha_flujo IS NOT NULL       THEN 'Generó flujo'
        WHEN u.especifico_norm LIKE 'REVOCATORIA%' THEN 'Revocó la cancelación'
        WHEN tk.retenido_ticket = 1           THEN 'Retenido'
        WHEN tk.no_retenido_ticket = 1        THEN 'En cola - no retenido'
        ELSE 'En cola - sin gestión de retención'
    END                                                     AS estado_cola,
    CURRENT_DATE()                                          AS fecha_corte
FROM cuenta cu
LEFT JOIN ultimo u  ON u.ACCOUNT_ID  = cu.ACCOUNT_ID
LEFT JOIN motivo m  ON m.ACCOUNT_ID  = cu.ACCOUNT_ID
LEFT JOIN flujo fl  ON fl.ACCOUNT_ID = cu.ACCOUNT_ID
LEFT JOIN ticket tk ON tk.ACCOUNT_ID = cu.ACCOUNT_ID
