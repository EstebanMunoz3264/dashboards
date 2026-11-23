let
    Origen = Csv.Document(File.Contents("data\excluded.csv"),[Delimiter=";", Columns=2, Encoding=1252, QuoteStyle=QuoteStyle.None]),
    #"Encabezados promovidos" = Table.PromoteHeaders(Origen, [PromoteAllScalars=true]),
    #"Tipo cambiado" = Table.TransformColumnTypes(#"Encabezados promovidos",{{"Causa", type text}, {"AccionesExternas", Int64.Type}})
in
    #"Tipo cambiado"
