let
    Origen = DeltaSharing.Contents("https://<region>.cloud.databricks.com/api/2.0/delta-sharing/metastores/<metastore_id>", [rowLimitHint=5000000]),
    share_churn = Origen{[Name="share_churn"]}[Data],
    db_gold = share_churn{[Name="db_gold"]}[Data],
    rms_disruptions1 = db_gold{[Name="rms_disruptions"]}[Data],
    filtro_fecha = Table.SelectRows(rms_disruptions1, each [evento_inicio] >= DateTime.From(Date.AddMonths(Date.From(DateTime.LocalNow()), -6)))
in
    filtro_fecha
