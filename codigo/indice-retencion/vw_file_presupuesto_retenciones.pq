let
  Origen = DeltaSharing.Contents("https://<region>.cloud.databricks.com/api/2.0/delta-sharing/metastores/<metastore_id>", [rowLimitHint = null]),
  #"Navegación 1" = Origen{[Name = "share_churn"]}[Data],
  #"Navegación 2" = #"Navegación 1"{[Name = "db_silver"]}[Data],
  #"Navegación 3" = #"Navegación 2"{[Name = "vw_file_presupuesto_retenciones"]}[Data]
in
  #"Navegación 3"
