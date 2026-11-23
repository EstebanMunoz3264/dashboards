let
    Origen = Excel.Workbook(File.Contents("data\Servicios_hfc.xlsx"), null, true),
    Hoja1_Sheet = Origen{[Item="Hoja1",Kind="Sheet"]}[Data],
    #"Encabezados promovidos" = Table.PromoteHeaders(Hoja1_Sheet, [PromoteAllScalars=true]),
    #"Tipo cambiado" = Table.TransformColumnTypes(#"Encabezados promovidos",{{"Ciudad", type text}, {"Internet", Int64.Type}, {"Telefonía", Int64.Type}, {"Televisión", Int64.Type}})
in
    #"Tipo cambiado"
