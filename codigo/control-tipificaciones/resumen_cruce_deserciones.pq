let
    Origen = DatabricksMultiCloud.Catalogs("<workspace>.cloud.databricks.com", "/sql/1.0/warehouses/<warehouse_id>", [Catalog="dwh_prod", Database=null, QueryTags=null, EnableAutomaticProxyDiscovery=null, Implementation="2.0", Protocol=null]),
    dwh_prod_Database = Origen{[Name="dwh_prod",Kind="Database"]}[Data],
    db_tmp_Schema = dwh_prod_Database{[Name="db_tmp",Kind="Schema"]}[Data],
    resumen_cruce_deserciones_Table = db_tmp_Schema{[Name="resumen_cruce_deserciones",Kind="Table"]}[Data]
in
    resumen_cruce_deserciones_Table
