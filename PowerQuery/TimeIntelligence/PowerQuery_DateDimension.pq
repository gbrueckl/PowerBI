let
  StartDate = #date(2019, 1, 1),
  EndDate = #date(Date.Year(DateTime.Date(DateTime.LocalNow())),12,31),
  CurrentDateForRelativeCalculation = Date.AddDays(DateTime.Date(DateTime.LocalNow()), 0),
  Culture = "en-US",
  DayCount = Duration.Days(Duration.From(EndDate - StartDate)),
  Source = List.Dates(StartDate,DayCount,#duration(1,0,0,0)),
  TableFromList = Table.FromList(Source, Splitter.SplitByNothing()),
  ChangedType = Table.TransformColumnTypes(TableFromList,{{"Column1", type date}}),
  RenamedColumns = Table.RenameColumns(ChangedType,{{"Column1", "Date"}}),
    InsertDateText = Table.AddColumn(RenamedColumns, "DateText", each Date.ToText([Date], "yyyy-MM-dd"), type text),
  InsertYear = Table.AddColumn(InsertDateText, "Year", each Text.From(Date.Year([Date])), type text),
    InsertYearNumber = Table.AddColumn(InsertYear, "YearNumber", each Date.Year([Date]), Int16.Type),
  InsertQuarterNumber = Table.AddColumn(InsertYearNumber, "QuarterNumber", each Date.QuarterOfYear([Date]), Int32.Type),
  InsertMonthNumber = Table.AddColumn(InsertQuarterNumber, "MonthNumber", each Date.Month([Date]), Int32.Type),
  InsertDayOfMonthNumber = Table.AddColumn(InsertMonthNumber, "DayOfMonthNumber", each Date.Day([Date]), Int32.Type),
  InsertDayOfWeekNumber = Table.AddColumn(InsertDayOfMonthNumber, "DayOfWeekNumber", each Date.DayOfWeek([Date], 1), Int32.Type),
  InsertDayOfWeek = Table.AddColumn(InsertDayOfWeekNumber, "DayOfWeek", each Date.ToText([Date], "dddd", Culture), type text),
    InsertDayOfYear = Table.AddColumn(InsertDayOfWeek, "DayOfYear", each Date.DayOfYear([Date]), Int16.Type),
  InsertDateInt = Table.AddColumn(InsertDayOfYear, "DateInt", each [YearNumber] * 10000 + [MonthNumber] * 100 + [DayOfMonthNumber], Int32.Type),
  InsertMonth = Table.AddColumn(InsertDateInt, "Month", each Date.ToText([Date], "MMMM", Culture), type text),
  InsertMonthYear = Table.AddColumn(InsertMonth, "MonthYear", each (try(Text.Range([Month],0,3)) otherwise Number.ToText([MonthNumber])) & " " & [Year], Text.Type),
  InsertMonthYearNumber = Table.AddColumn(InsertMonthYear, "MonthYearNumber", each [YearNumber] * 100 + [MonthNumber], Int32.Type),
  InsertQuarter = Table.AddColumn(InsertMonthYearNumber, "Quarter", each "Q " & Number.ToText([QuarterNumber]), type text),
  InsertQuarterYear = Table.AddColumn(InsertQuarter, "QuarterYear", each "Q" & Number.ToText([QuarterNumber]) & " " & [Year], type text),
  InsertQuarterYearNumber = Table.AddColumn(InsertQuarterYear, "QuarterYearNumber", each [YearNumber] * 10 + [QuarterNumber], Int32.Type),

  InsertRelativeDay = Table.AddColumn(InsertQuarterYearNumber, "RelativeDay", each Duration.Days([Date] - CurrentDateForRelativeCalculation), Int32.Type),
  InsertRelativeYear = Table.AddColumn(InsertRelativeDay , "RelativeYear", each Date.Year([Date]) - Date.Year(CurrentDateForRelativeCalculation ), Int32.Type),
  InsertRelativeMonth = Table.AddColumn(InsertRelativeYear, "RelativeMonth", each (Date.Year([Date]) * 12 + Date.Month([Date])) 
      - (Date.Year(CurrentDateForRelativeCalculation ) * 12 + Date.Month(CurrentDateForRelativeCalculation )), Int32.Type),
  InsertRelativeQuarter =Table.AddColumn(InsertRelativeMonth, "RelativeQuarter", each (Date.Year([Date]) * 4 + Date.QuarterOfYear([Date])) 
      - (Date.Year(CurrentDateForRelativeCalculation ) * 4 + Date.QuarterOfYear(CurrentDateForRelativeCalculation)), Int32.Type),
  BufferedTable = Table.Buffer(InsertRelativeQuarter)
in
  BufferedTable