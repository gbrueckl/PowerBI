let
    fn_DateTableWithCurrentCalculations = (
        ExistingDateTable as table, 
        CurrentDefinitions as table,
        DateColumnName as text) => 
    let

        ExistingDateTableBuffered = Table.Buffer(ExistingDateTable),

        BaseDateTableWithType = 
        let
            Source = ExistingDateTableBuffered,
            CalculatedDates = List.Buffer(CurrentDefinitionsEvaluated[Date]),
            #"Added Custom" = Table.AddColumn(Source, "Type", each if List.Contains(CalculatedDates, Record.Field(_, DateColumnName)) then "date values" else "regular dates", type text)
        in
            #"Added Custom",

        CurrentDefinitionsWithFunctions =
        let
            Source = CurrentDefinitions,
            #"Replace DateColumn References" = Table.TransformColumns(Source,{{"Filter", (x) => Text.Replace(x, "<<DateColumn>>", "[" & DateColumnName & "]"), type text}}),
            #"Added Transformation" = Table.AddColumn(#"Replace DateColumn References", "Transformation", each (x as text) as text => [NewValue], type function),
            #"Added TableTransformation" = Table.AddColumn(#"Added Transformation", "TableTransformation", each {[Column],[Transformation], type text}, type list),
            #"Added Transformation_Agg" = Table.AddColumn(#"Added TableTransformation", "Transformation_Agg", each (x as table) as text => List.SingleOrDefault(List.Intersect({Table.Column(x, [Column]), CurrentDefinitions_Input[NewValue]}), List.First(Table.Column(x, [Column])))),
            #"Added TableTransformation_Agg" = Table.AddColumn(#"Added Transformation_Agg", "TableTransformation_Agg", each {[Column], [Transformation_Agg], type text}, type list),
            #"Grouped Rows" = Table.Group(#"Added TableTransformation_Agg", {"Filter"}, {{"Transformations", each List.Combine({[TableTransformation]}), type list}, {"Transformations_Agg", each List.Combine({[TableTransformation_Agg]}), type list}})
        in
            #"Grouped Rows",

        CurrentDefinitionsEvaluated = 
        let
            Source = CurrentDefinitionsWithFunctions,
            #"Added BaseRows" = Table.AddColumn(Source, "BaseRows", each Table.SelectRows(ExistingDateTable, Expression.Evaluate("each " & [Filter], Environment_DateFunctions)), type table),
            #"Added NewDateRows" = Table.AddColumn(#"Added BaseRows", "NewDateRows", each Table.TransformColumns([BaseRows], [Transformations]), type table),
            #"Expanded NewDateRows" = Table.Combine(#"Added NewDateRows"[NewDateRows])
        in
            #"Expanded NewDateRows",

        Environment_DateFunctions = 
        let
            Source = [
                Date.IsInPreviousDay = Date.IsInPreviousDay,
                Date.IsInPreviousNDays = Date.IsInPreviousNDays,
                Date.IsInCurrentDay = Date.IsInCurrentDay,
                Date.IsInNextDay = Date.IsInNextDay,
                Date.IsInNextNDays = Date.IsInNextNDays,
                Date.IsInPreviousWeek = Date.IsInPreviousWeek,
                Date.IsInPreviousNWeeks = Date.IsInPreviousNWeeks,
                Date.IsInCurrentWeek = Date.IsInCurrentWeek,
                Date.IsInNextWeek = Date.IsInNextWeek,
                Date.IsInNextNWeeks = Date.IsInNextNWeeks,
                Date.IsInPreviousMonth = Date.IsInPreviousMonth,
                Date.IsInPreviousNMonths = Date.IsInPreviousNMonths,
                Date.IsInCurrentMonth = Date.IsInCurrentMonth,
                Date.IsInNextMonth = Date.IsInNextMonth,
                Date.IsInNextNMonths = Date.IsInNextNMonths,
                Date.IsInPreviousQuarter = Date.IsInPreviousQuarter,
                Date.IsInPreviousNQuarters = Date.IsInPreviousNQuarters,
                Date.IsInCurrentQuarter = Date.IsInCurrentQuarter,
                Date.IsInNextQuarter = Date.IsInNextQuarter,
                Date.IsInNextNQuarters = Date.IsInNextNQuarters,
                Date.IsInPreviousYear = Date.IsInPreviousYear,
                Date.IsInPreviousNYears = Date.IsInPreviousNYears,
                Date.IsInCurrentYear = Date.IsInCurrentYear,
                Date.IsInNextYear = Date.IsInNextYear,
                Date.IsInNextNYears = Date.IsInNextNYears,
                Date.IsInYearToDate = Date.IsInYearToDate,
                Date.MonthName = Date.MonthName,
                Date.DayOfWeekName = Date.DayOfWeekName,
                Date.FromText = Date.FromText,
                Date.From = Date.From,
                Date.ToText = Date.ToText,
                Date.ToRecord = Date.ToRecord,
                Date.Year = Date.Year,
                Date.Month = Date.Month,
                Date.Day = Date.Day,
                Date.AddDays = Date.AddDays,
                Date.AddWeeks = Date.AddWeeks,
                Date.AddMonths = Date.AddMonths,
                Date.AddQuarters = Date.AddQuarters,
                Date.AddYears = Date.AddYears,
                Date.IsLeapYear = Date.IsLeapYear,
                Date.StartOfYear = Date.StartOfYear,
                Date.StartOfQuarter = Date.StartOfQuarter,
                Date.StartOfMonth = Date.StartOfMonth,
                Date.StartOfWeek = Date.StartOfWeek,
                Date.StartOfDay = Date.StartOfDay,
                Date.EndOfYear = Date.EndOfYear,
                Date.EndOfQuarter = Date.EndOfQuarter,
                Date.EndOfMonth = Date.EndOfMonth,
                Date.EndOfWeek = Date.EndOfWeek,
                Date.EndOfDay = Date.EndOfDay,
                Date.DayOfWeek = Date.DayOfWeek,
                Date.DayOfYear = Date.DayOfYear,
                Date.DaysInMonth = Date.DaysInMonth,
                Date.QuarterOfYear = Date.QuarterOfYear,
                Date.WeekOfMonth = Date.WeekOfMonth,
                Date.WeekOfYear = Date.WeekOfYear,
                Date.Type = Date.Type
            ]
        in
            Source,

        OverlapsWithType = 
        let
            Source = CurrentDefinitionsEvaluated,
            #"Filtered Rows" = Table.SelectRows(Source, Expression.Evaluate("each " & Text.Combine(CurrentDefinitionsWithFunctions[Filter], " or "), Environment_DateFunctions)),
            Transformations_Current = List.Distinct(List.Combine(CurrentDefinitionsWithFunctions[Transformations_Agg]), (x) => x{0}),
            Transformations_Other = List.Transform(List.RemoveMatchingItems(Table.ColumnNames(BaseDateTableWithType), List.Combine({CurrentDefinitions[Column], {DateColumnName}})), (y) => {y, (x as table) =>  List.First(Table.Column(x, y)), type any}),
            #"Grouped Rows" = Table.Group(#"Filtered Rows", {DateColumnName}, List.Combine({Transformations_Current, Transformations_Other})),
            #"Change Table Type" = Value.ReplaceType(Table.SelectColumns(#"Grouped Rows",Table.ColumnNames(ExistingDateTable)), Value.Type(ExistingDateTable)),
            #"Added Custom" = Table.AddColumn(#"Change Table Type", "Type", each "current values", type text)
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