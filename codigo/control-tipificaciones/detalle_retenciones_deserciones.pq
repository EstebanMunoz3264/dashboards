let
    Origen = DatabricksMultiCloud.Catalogs("<workspace>.cloud.databricks.com", "/sql/1.0/warehouses/<warehouse_id>", [Catalog="dwh_prod", Database=null, QueryTags=null, EnableAutomaticProxyDiscovery=null, Implementation="2.0", Protocol=null]),
    dwh_prod_Database = Origen{[Name="dwh_prod",Kind="Database"]}[Data],
    db_tmp_Schema = dwh_prod_Database{[Name="db_tmp",Kind="Schema"]}[Data],
    detalle_retenciones_deserciones_Table = db_tmp_Schema{[Name="detalle_retenciones_deserciones",Kind="Table"]}[Data],
    #"Departamento_Ajustado" = Table.TransformColumns(detalle_retenciones_deserciones_Table, {{"Departamento", each if _ = "360" or _ = "ServicioMail" then "CallCenter" else _, type text}}),
    #"Ordenado_UltimoTicket" = Table.Sort(#"Departamento_Ajustado", {{"Fecha_Llamada", Order.Descending}, {"Ticket", Order.Descending}}),
    #"Agrupado_CuentaMes" = Table.Group(#"Ordenado_UltimoTicket", {"Cuenta", "MES"}, {{"__fila", each Table.FirstN(_,1){0}, type record}}),
    #"SoloRegistro" = Table.SelectColumns(#"Agrupado_CuentaMes", {"__fila"}),
    #"Cuentas_Unicas" = Table.ExpandRecordColumn(#"SoloRegistro", "__fila", Table.ColumnNames(#"Ordenado_UltimoTicket"))
in
    #"Cuentas_Unicas"
