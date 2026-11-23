let
  Origen = DatabricksMultiCloud.Catalogs("<workspace>.cloud.databricks.com", "/sql/1.0/warehouses/<warehouse_id>", [Catalog = null, Database = null, QueryTags = null, EnableAutomaticProxyDiscovery = "enabled", Implementation = "2.0", Protocol = null]),
  #"Navegación 1" = Origen{[Name = "dwh_prod", Kind = "Database"]}[Data],
  #"Navegación 2" = #"Navegación 1"{[Name = "db_tmp", Kind = "Schema"]}[Data],
  #"Navegación 3" = #"Navegación 2"{[Name = "cascada_retenidos_detalle", Kind = "Table"]}[Data]
in
  #"Navegación 3"
