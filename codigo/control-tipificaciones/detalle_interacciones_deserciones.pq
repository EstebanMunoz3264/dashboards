let
    Origen = DatabricksMultiCloud.Catalogs("<workspace>.cloud.databricks.com", "/sql/1.0/warehouses/<warehouse_id>", [Catalog="dwh_prod", Database=null, QueryTags=null, EnableAutomaticProxyDiscovery=null, Implementation="2.0", Protocol=null]),
    dwh_prod_Database = Origen{[Name="dwh_prod",Kind="Database"]}[Data],
    db_tmp_Schema = dwh_prod_Database{[Name="db_tmp",Kind="Schema"]}[Data],
    detalle_interacciones_deserciones_Table = db_tmp_Schema{[Name="detalle_interacciones_deserciones",Kind="Table"]}[Data],
    #"Ordenado_UltimoTicket" = Table.Sort(detalle_interacciones_deserciones_Table, {{"FECHA_CREACION", Order.Descending}, {"FECHA_CIERRE", Order.Descending}, {"ID", Order.Descending}}),
    #"Agrupado_CuentaMes" = Table.Group(#"Ordenado_UltimoTicket", {"ACCOUNT_ID", "MES"}, {{"__fila", each Table.FirstN(_,1){0}, type record}}),
    #"SoloRegistro" = Table.SelectColumns(#"Agrupado_CuentaMes", {"__fila"}),
    #"Cuentas_Unicas" = Table.ExpandRecordColumn(#"SoloRegistro", "__fila", Table.ColumnNames(#"Ordenado_UltimoTicket"))
in
    #"Cuentas_Unicas"
