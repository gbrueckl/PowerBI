let
    MinuteSteps = 15,
    // Now create a Time type list for a total of 1440 minutes, incrementing one minute at a time
    Source = List.Times(#time(0, 0, 0), 24 * 60 / MinuteSteps, #duration(0,0,MinuteSteps,0)),
    // Turn that list into a one column table
    TableFromList = Table.FromList(Source, Splitter.SplitByNothing()), 
    // Change that table's one column to type Time
    ChangedType = Table.TransformColumnTypes(TableFromList,{{"Column1", type time}}),
    // Rename column to Time
    RenamedColumns = Table.RenameColumns(ChangedType,{{"Column1", "Time"}}),
    // Start inserting columns for each unit of time to represent in the dimension
    InsertHour = Table.AddColumn(RenamedColumns, "Hour", each Time.StartOfHour([Time]), Time.Type),
    InsertMinute = Table.AddColumn(InsertHour, "Minute", each Time.Minute([Time]), Int64.Type),
    ChangedTypeHour = Table.TransformColumnTypes(InsertMinute,{{"Hour", type time}}),
    // Creating levels in the hierarchy that might be useful for reporting. Omit if not useful to yours
    InsertQuarterHour = Table.AddColumn(ChangedTypeHour, "Quarter Hour", each if [Minute]<15 then [Hour] else if [Minute] < 30 then Value.Add([Hour],#duration(0,0,15, 0)) else if [Minute] < 45 then Value.Add([Hour],#duration(0,0,30, 0)) else Value.Add([Hour],#duration(0,0,45, 0)), Time.Type),  ChangedTypeQtrHr = Table.TransformColumnTypes(InsertQuarterHour,{{"Quarter Hour", type time}}),  ReorderedColumns = Table.ReorderColumns(ChangedTypeQtrHr,{"Time", "Hour", "Quarter Hour", "Minute"}),  InsertHourNumber = Table.AddColumn(ReorderedColumns, "Hour Number", each Time.Hour([Time]), Int64.Type),  InsertPeriod = Table.AddColumn(InsertHourNumber, "Period of Day",   each if [Hour Number] >= 0 and [Hour Number] < 4 then "After Midnight" else   if [Hour Number] >= 4 and [Hour Number] < 8 then "Early Morning" else  if [Hour Number] >= 8 and [Hour Number] < 12 then "Late Morning" else  if [Hour Number] >= 12 and [Hour Number] < 16 then "Afternoon" else  if [Hour Number] >= 16 and [Hour Number] < 20 then "Evening" else "Late Night", Text.Type),  InsertPeriodSort = Table.AddColumn(InsertPeriod, "PeriodSort", each   if [Hour Number] >= 0 and [Hour Number] < 4 then 0 else   if [Hour Number] >= 4 and [Hour Number] < 8 then 1 else  if [Hour Number] >= 8 and [Hour Number] < 12 then 2 else  if [Hour Number] >= 12 and [Hour Number] < 16 then 3 else  if [Hour Number] >= 16 and [Hour Number] < 20 then 4 else 5, Int64.Type),
    InsertTimeKey = Table.AddColumn(InsertPeriodSort, "TimeKey", each Time.ToText([Time], "HHmm"), type text)
in
    InsertTimeKey