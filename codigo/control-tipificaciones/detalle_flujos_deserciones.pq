let
    Origen = DatabricksMultiCloud.Catalogs("<workspace>.cloud.databricks.com", "/sql/1.0/warehouses/<warehouse_id>", [Catalog="dwh_prod", Database=null, QueryTags=null, EnableAutomaticProxyDiscovery=null, Implementation="2.0", Protocol=null]),
    dwh_prod_Database = Origen{[Name="dwh_prod",Kind="Database"]}[Data],
    db_tmp_Schema = dwh_prod_Database{[Name="db_tmp",Kind="Schema"]}[Data],
    detalle_flujos_deserciones_Table = db_tmp_Schema{[Name="detalle_flujos_deserciones",Kind="Table"]}[Data],
    #"Tipo cambiado" = Table.TransformColumnTypes(detalle_flujos_deserciones_Table,{{"CITEM_ID", type text}, {"ACCOUNT_ID", type text}, {"CONTRACT_ID", type text}, {"ID_PROCESO_BAJA", type text}, {"ID_PROCESO_RAIZ_BAJA", type text}}),
    #"Ordenado_UltimoProceso" = Table.Sort(#"Tipo cambiado", {{"FECHA_PROCESO_RAIZ_BAJA", Order.Descending}, {"CITEM_ID", Order.Descending}, {"FECHA_TERMINACION", Order.Descending}, {"ID_PROCESO_BAJA", Order.Descending}}),
    #"Agrupado_CuentaMes" = Table.Group(#"Ordenado_UltimoProceso", {"ACCOUNT_ID", "MES"}, {{"__fila", each Table.FirstN(_,1){0}, type record}}),
    #"SoloRegistro" = Table.SelectColumns(#"Agrupado_CuentaMes", {"__fila"}),
    #"Cuentas_Unicas" = Table.ExpandRecordColumn(#"SoloRegistro", "__fila", Table.ColumnNames(#"Ordenado_UltimoProceso"))
in
    #"Cuentas_Unicas"
