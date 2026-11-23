let
    Origen = Excel.Workbook(File.Contents("data\SLA.xlsx"), null, true),
    SLA_Sheet = Origen{[Item="SLA",Kind="Sheet"]}[Data],
    #"Encabezados promovidos" = Table.PromoteHeaders(SLA_Sheet, [PromoteAllScalars=true]),
    #"Tipo cambiado" = Table.TransformColumnTypes(#"Encabezados promovidos",{{"Categoría", type text}, {"TipoSLA", type text}, {"SLA", Int64.Type}})
in
    #"Tipo cambiado"
