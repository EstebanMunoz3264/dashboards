let
    Origen = DeltaSharing.Contents(
        "https://<region>.cloud.databricks.com/api/2.0/delta-sharing/metastores/<metastore_id>", 
        [rowLimitHint = null]
    ),
    share_churn = Origen{[Name = "share_churn"]}[Data],
    db_gold = share_churn{[Name = "db_gold"]}[Data],
    Tabla = db_gold{[Name = "tickets_deserciones"]}[Data],

    Filtro_Retencion = Table.SelectRows(Tabla, each 
        [Retencion] = "SI" or [Retencion] = "NO" or [Retencion] = "SI CRM"
    ),
    Filtro_Depto = Table.SelectRows(Filtro_Retencion, each ([Departamento] <> null and [Departamento] <> "Contratistas")),
    Filtro_Fecha = Table.SelectRows(Filtro_Depto, each 
        DateTime.Date([Fecha_de_Ingreso]) >= #date(2025, 1, 1)
    ),
    #"Tipo cambiado" = Table.TransformColumnTypes(Filtro_Fecha,{{"Fecha_Llamada", type date}, {"Fecha_de_Ingreso", type date}}),
    #"Valor reemplazado" = Table.ReplaceValue(#"Tipo cambiado","SI CRM","SI",Replacer.ReplaceText,{"Retencion"}),
    #"Valor reemplazado1" = Table.ReplaceValue(#"Valor reemplazado","360","CallCenter",Replacer.ReplaceText,{"Departamento"}),
    #"Valor reemplazado2" = Table.ReplaceValue(#"Valor reemplazado1","ServicioMail","CallCenter",Replacer.ReplaceText,{"Departamento"}),
    #"Filas filtradas" = Table.SelectRows(#"Valor reemplazado2", each true)
in
    #"Filas filtradas"
