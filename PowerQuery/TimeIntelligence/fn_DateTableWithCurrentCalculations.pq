let
    fn_DateTableWithCurrentCalculations = (
        BaseDateTable as table, 
        CurrentTransformations as table,
        optional DateColumnName as nullable text) => 
    let
        // Parameters
        DateColumnNameValue = if DateColumnName = null then "Date" else DateColumnName,
        BaseDateTableBuffered = Table.Buffer(BaseDateTable),

        BaseDateTableWithType = 
        let
            Source = BaseDateTableBuffered,
            CalculatedDates = List.Buffer(CurrentTransformationsWithType[Date]),
            #"Added Custom" = Table.AddColumn(Source, "Type", each if List.Contains(CalculatedDates, Record.Field(_, DateColumnNameValue)) then "date values" else "regular", type text)
        in
            #"Added Custom",

        CurrentTransformationsWithFunctions = 
        let
            Source = CurrentTransformations,
            #"Added Transformation" = Table.AddColumn(Source, "Transformation", each (x as text) as text => [NewValue], type function),
            #"Added TableTransformation" = Table.AddColumn(#"Added Transformation", "TableTransformation", each {[Column],[Transformation], type text}, type list),
            #"Added Custom" = Table.AddColumn(#"Added TableTransformation", "Transformation_Agg", each (x as table) as text => List.SingleOrDefault(List.Intersect({Table.Column(x, [Column]), CurrentTransformations_Input[NewValue]}), List.First(Table.Column(x, [Column])))),
            #"Added Custom1" = Table.AddColumn(#"Added Custom", "TableTransformation_Agg", each {[Column], [Transformation_Agg], type text}, type list),
            #"Grouped Rows" = Table.Group(#"Added Custom1", {"Filter"}, {{"Transformations", each List.Combine({[TableTransformation]}), type list}, {"Transformations_Agg", each List.Combine({[TableTransformation_Agg]}), type list}})
        in
            #"Grouped Rows",

        CurrentTransformationsWithType = 
        let
            Source = CurrentTransformationsWithFunctions,
            #"Added BaseRows" = Table.AddColumn(Source, "BaseRows", each Table.SelectRows(BaseDateTable, Expression.Evaluate("each " & [Filter])), type table),
            #"Added NewDateRows" = Table.AddColumn(#"Added BaseRows", "NewDateRows", each Table.TransformColumns([BaseRows], [Transformations]), type table),
            #"Expanded NewDateRows" = Table.Combine(#"Added NewDateRows"[NewDateRows]),
            #"Added Type column" = Table.AddColumn(#"Expanded NewDateRows", "Type", each "calculated", type text)
        in
            #"Added Type column",


        OverlapsWithType =
        let
            Source = CurrentTransformationsWithType,
            #"Filtered Rows" = Table.SelectRows(Source, Expression.Evaluate("each " & Text.Combine(CurrentTransformationsWithFunctions[Filter], " or "))),
            Transformations_Current = List.Distinct(List.Combine(CurrentTransformationsWithFunctions[Transformations_Agg]), (x) => x{0}),
            Transformations_Other = List.Transform(List.RemoveMatchingItems(Table.ColumnNames(BaseDateTableWithType), List.Combine({CurrentTransformations[Column], {DateColumnNameValue}})), (y) => {y, (x as table) =>  List.First(Table.Column(x, y)), type any}),
            #"Grouped Rows" = Table.Group(#"Filtered Rows", {"Date"}, List.Combine({Transformations_Current, Transformations_Other})),
            #"Change Tyble Type" = Value.ReplaceType(Table.SelectColumns(#"Grouped Rows",Table.ColumnNames(BaseDateTable)), Value.Type(BaseDateTable)),
            #"Added Custom" = Table.AddColumn(#"Change Tyble Type", "Type", each "current texts", type text)
        in
            #"Added Custom",

        result = Table.Combine({BaseDateTableWithType, OverlapsWithType})
    in
        result,

    documentation = [
        Documentation.Name =  "fn_DateTableWithCurrentCalculations",
        Documentation.Description = "The function extends an existing date-table with new rows that contain generic values for 'Current Month', 'Today', etc. which can be used for generic selection of relative time intervals.",
        Documentation.LongDescription = "The function extends an existing date-table with new rows that contain generic values for 'Current Month', 'Today', etc. which can be used for generic selection of relative time intervals.",
        Documentation.Category = "Table",
        Documentation.Source = "https://github.com/gbrueckl/PowerBI/PowerQuery/TimeIntelligence",
        Documentation.Version = "1.0",
        Documentation.Author = "Gerhard Brueckl, paiqo GmbH"
        ]
in
    Value.ReplaceType(fn_DateTableWithCurrentCalculations, Value.ReplaceMetadata(Value.Type(fn_DateTableWithCurrentCalculations), documentation))