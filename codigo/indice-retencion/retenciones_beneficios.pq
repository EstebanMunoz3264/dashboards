let
    Origen = DeltaSharing.Contents("https://<region>.cloud.databricks.com/api/2.0/delta-sharing/metastores/<metastore_id>", [rowLimitHint=null]),
    share_churn = Origen{[Name="share_churn"]}[Data],
    db_gold = share_churn{[Name="db_gold"]}[Data],
    retenciones_beneficios1 = db_gold{[Name="retenciones_beneficios"]}[Data],
    #"Tipo cambiado" = Table.TransformColumnTypes(retenciones_beneficios1,{{"Ticket", type text}, {"Fecha_Llamada", type date}, {"Fecha_de_Ingreso", type date}}),
    #"Puntaje de confiabilidad" = Table.AddColumn(#"Tipo cambiado", "PuntajeConfiabilidad", each
        ( if [VALOR_PLAN_ACTUAL] <> null and [ARPUCITEM_SIN_IVA_REPORTE] <> null
                and Number.Round([VALOR_PLAN_ACTUAL], 2) = Number.Round([ARPUCITEM_SIN_IVA_REPORTE], 2)
          then 100 else 0 )
        + ( if [FECHA_ACTIVACION_RETENCION] = null then 50 else 0 )
        + ( if [ORIGEN] = "ASIGPROMO" then 0 else 10 ),
        Int64.Type),
    #"Columnas MejorFila" = List.RemoveItems(Table.ColumnNames(#"Puntaje de confiabilidad"), {"Ticket"}),
    #"Agrupado por Ticket" = Table.Group(#"Puntaje de confiabilidad", {"Ticket"}, {{"MejorFila", each Table.FirstN(Table.Sort(_, {{"PuntajeConfiabilidad", Order.Ascending}, {"Fecha_Llamada", Order.Descending}}), 1)}}),
    #"Duplicados expandidos" = Table.ExpandTableColumn(#"Agrupado por Ticket", "MejorFila", #"Columnas MejorFila"),
    #"Puntaje quitado" = Table.RemoveColumns(#"Duplicados expandidos", {"PuntajeConfiabilidad"}),
    #"Rechazados excluidos" = Table.SelectRows(#"Puntaje quitado", each not (
        List.Contains({"Rechazado", "Ticket Rechazado"}, [estado_ticket], Comparer.OrdinalIgnoreCase)
        and [Fecha_de_Ingreso] >= #date(2026,7,1)
    )),
    #"AñoMes agregado" = Table.AddColumn(#"Rechazados excluidos", "AñoMes", each Date.Year([Fecha_Llamada]) * 100 + Date.Month([Fecha_Llamada]), Int64.Type),
    // Desempate deterministico: mismo dia -> ticket mayor (mas reciente). Table.Buffer fija el orden antes de agrupar.
    #"Ordenado por fecha" = Table.Buffer(Table.Sort(#"AñoMes agregado", {{"Fecha_Llamada", Order.Descending}, {each try Number.From([Ticket]) otherwise 0, Order.Descending}})),
    #"Agrupado Cuenta Mes" = Table.Group(#"Ordenado por fecha", {"Cuenta", "AñoMes"}, {{"Ultimo", each Table.FirstN(_,1)}}),
    #"Columnas a expandir" = List.RemoveItems(Table.ColumnNames(#"Ordenado por fecha"), {"Cuenta", "AñoMes"}),
    #"Expandido Ultimo" = Table.ExpandTableColumn(#"Agrupado Cuenta Mes", "Ultimo", #"Columnas a expandir"),
    #"AñoMes quitado" = Table.RemoveColumns(#"Expandido Ultimo", {"AñoMes"}),
    #"Tipos restaurados" = Table.TransformColumnTypes(#"AñoMes quitado", {
        {"Fecha_Llamada", type date},
        {"Fecha_de_Ingreso", type date},
        {"FECHA_ACTIV_PLAN_ACTUAL", type datetime},
        {"VALOR_PLAN_ACTUAL", type number},
        {"VALOR_PLAN_ANTIGUO", type number},
        {"INCREMENTO", type number},
        {"ARPU_INTERNET", type number},
        {"ARPU_CUENTA", type number},
        {"ARPUCITEM_SIN_IVA_REPORTE", type number},
        {"VALOR_FACTURACION_MENSUAL", type number}
    })
in
    #"Tipos restaurados"
