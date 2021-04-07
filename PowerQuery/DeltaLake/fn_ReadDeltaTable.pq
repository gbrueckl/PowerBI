(
    DeltaTableFolderContent as table,
    optional DeltaTableOptions as record
) as table =>

let

    DeltaTableVersion = if DeltaTableOptions = null or not Record.HasFields(DeltaTableOptions, "Version") then null else Record.Field(DeltaTableOptions, "Version"),
    DeltaTableFolderContent_wFullPath = 
    let 
        #"Added Full_Path" = Table.AddColumn(DeltaTableFolderContent, "Full_Path", each Text.Replace([Folder Path] & [Name], "=", "%3D")),
        Buffered = Table.Buffer(#"Added Full_Path")
    in
        Buffered,
        
    #"Delimiter" = 
    let
        Delimiter = if Text.Contains(DeltaTableFolderContent_wFullPath{0}[Full_Path], "//") then "/" else "\"
    in
        Delimiter,

    #"_delta_log Folder" = 
    let
       Source = DeltaTableFolderContent_wFullPath,
       #"Filtered Rows" = Table.SelectRows(Source, each Text.Contains([Full_Path], Delimiter & "_delta_log" & Delimiter)),
       #"Added Version" = Table.AddColumn(#"Filtered Rows", "Version", each try Int64.From(Text.BeforeDelimiter([Name], ".")) otherwise -1, Int64.Type),
       #"Filtered RequestedVersion" = if DeltaTableVersion = null then #"Added Version" else Table.SelectRows(#"Added Version", each [Version] <= DeltaTableVersion),
       buffered = Table.Buffer(#"Filtered RequestedVersion")
    in
        buffered,

    #"DeltaTablePath" = 
    let
        DeltaTablePath = Text.Combine(List.RemoveLastN(Text.Split(#"_delta_log Folder"{0}[Full_Path], Delimiter), 2), Delimiter) & Delimiter
    in
        DeltaTablePath,

    #"_last_checkpoint" = 
    let
        #"_delta_log" = #"_delta_log Folder",
        #"Filtered Rows" = Table.SelectRows(_delta_log, each Text.EndsWith([Name], "_last_checkpoint")),
        #"Added Custom" = Table.AddColumn(#"Filtered Rows", "JsonContent", each Json.Document([Content])),
        JsonContent = #"Added Custom"{0}[JsonContent],
        CheckEmpty = if Table.RowCount(#"Filtered Rows") = 0 then [Size=-1, version=-1] else JsonContent,
        LatestCheckPointWithParts = if Record.HasFields(CheckEmpty, "parts") then CheckEmpty else Record.AddField(CheckEmpty, "parts", 1),

        #"Filtered Rows Version" = Table.SelectRows(#"_delta_log", each Text.EndsWith([Name], ".checkpoint.parquet")),
        MaxVersion = try Table.Group(#"Filtered Rows Version", {}, {{"MaxVersion", each List.Max([Version]), type number}}){0}[MaxVersion] otherwise -1,
        #"Filtered Rows MaxVersion" = Table.SelectRows(#"Filtered Rows Version", each [Version] = MaxVersion),
        CheckpointFromVersion = [version=try MaxVersion otherwise -1, size=-1, parts = Table.RowCount(#"Filtered Rows MaxVersion")],

        LastCheckpoint = Table.Buffer(Table.FromRecords({if DeltaTableVersion = null then LatestCheckPointWithParts else CheckpointFromVersion})){0}
    in
        LastCheckpoint,

    #"Checkpoint Files" = 
    let
        LastCheckpointFile = {1..Record.Field(_last_checkpoint, "parts")},
        #"Converted to Table" = Table.FromList(LastCheckpointFile, Splitter.SplitByNothing(), {"part"}, null, ExtraValues.Error),
        #"Add Version" = Table.AddColumn(#"Converted to Table", "version", each Record.Field(_last_checkpoint, "version")),
        #"Add SingleFile" = Table.AddColumn(#"Add Version", "file_name", each Text.PadStart(Text.From([version]), 20, "0") & ".checkpoint.parquet", Text.Type),
        #"Add MultipleFiles" = Table.AddColumn(#"Add Version", "file_name", each Text.PadStart(Text.From([version]), 20, "0") & ".checkpoint." & Text.PadStart(Text.From([part]), 10, "0") & "." & Text.PadStart(Text.From(Record.Field(_last_checkpoint, "parts")), 10, "0") & ".parquet", Text.Type),
        AllFiles = Table.SelectColumns(if Record.Field(_last_checkpoint, "parts") = 1 then #"Add SingleFile" else #"Add MultipleFiles", "file_name"),
        AllFiles_BufferedList = List.Buffer(Table.ToList(AllFiles)),
        Content = Table.SelectRows(#"_delta_log Folder", each List.Count(List.Select(AllFiles_BufferedList, (inner) => Text.EndsWith([Name], inner))) > 0)
    in
        Content,

    #"Logs Checkpoint" = 
    let
        Source = #"Checkpoint Files",
        #"Parsed Logs" = Table.AddColumn(Source, "Custom", each Parquet.Document([Content])),
        #"Expanded Logs" = Table.ExpandTableColumn(#"Parsed Logs", "Custom", {"add", "remove", "metaData", "commitInfo", "protocol"}, {"add", "remove", "metaData", "commitInfo", "protocol"}),
        #"Removed Other Columns" = Table.SelectColumns(#"Expanded Logs",{"Version", "add", "remove", "metaData", "commitInfo", "protocol"})
    in
        #"Removed Other Columns",

    #"Latest Log Files" = 
    let
        Source = #"_delta_log Folder",
        #"Filtered Rows" = Table.SelectRows(Source, each ([Extension] = ".json")),
        #"Filtered Rows1" = Table.SelectRows(#"Filtered Rows", each [Version] > Record.Field(_last_checkpoint, "version"))
    in
        #"Filtered Rows1",

    #"Logs JSON" = 
    let
        Source = #"Latest Log Files",
        #"Added Custom" = Table.AddColumn(Source, "JsonContent", each Lines.FromBinary([Content])),
        #"Expanded JsonContent" = Table.ExpandListColumn(#"Added Custom", "JsonContent"),
        #"Parsed Logs" = Table.TransformColumns(#"Expanded JsonContent",{{"JsonContent", Json.Document}}),
        #"Expanded Logs" = Table.ExpandRecordColumn(#"Parsed Logs", "JsonContent", {"add", "remove", "metaData", "commitInfo", "protocol"}),
        #"Removed Other Columns" = Table.SelectColumns(#"Expanded Logs",{"Version", "add", "remove", "metaData", "commitInfo", "protocol"})
    in
        #"Removed Other Columns",

    #"Logs ALL" = 
    let
        Source = Table.Combine({#"Logs Checkpoint", #"Logs JSON"}),
        #"Added timestamp" = Table.AddColumn(Source, "log_timestamp", each if [add] <> null then Record.Field([add], "modificationTime") else 
    if [remove] <> null then Record.Field([remove], "deletionTimestamp") else 
    if [commitInfo] <> null then Record.Field([commitInfo], "timestamp") else 
    if [metaData] <> null then Record.Field([metaData], "createdTime") else null, Int64.Type),
        #"Added datetime" = Table.AddColumn(#"Added timestamp", "log_datetime", each try #datetime(1970,1,1,0,0,0)+#duration(0,0,0,[log_timestamp]/1000) otherwise null, DateTime.Type)
    in
        #"Added datetime",

    #"metadata_columns" = 
    let
        Source = #"Logs ALL",
        #"Filtered Rows1" = Table.SelectRows(Source, each ([metaData] <> null)),
        MaxVersion = Table.Group(#"Filtered Rows1", {}, {{"MaxVersion", each List.Max([Version]), type number}}){0}[MaxVersion],
        #"Filtered Rows2" = Table.SelectRows(#"Filtered Rows1", each [Version] = MaxVersion),
        #"Kept First Rows" = Table.FirstN(#"Filtered Rows2",1),
        #"Removed Other Columns" = Table.SelectColumns(#"Kept First Rows",{"metaData"}),
        #"Expanded metaData" = Table.ExpandRecordColumn(#"Removed Other Columns", "metaData", {"schemaString", "partitionColumns"}, {"schemaString", "partitionColumns"}),
        #"Filtered Rows" = Table.SelectRows(#"Expanded metaData", each ([schemaString] <> null)),
        JSON = Table.TransformColumns(#"Filtered Rows",{{"schemaString", Json.Document}}),
        #"Expanded schemaString" = Table.ExpandRecordColumn(JSON, "schemaString", {"fields"}, {"fields"}),
        #"Expanded fields" = Table.ExpandListColumn(#"Expanded schemaString", "fields"),
        #"Expanded fields1" = Table.ExpandRecordColumn(#"Expanded fields", "fields", {"name", "type", "nullable", "metadata"}, {"name", "type", "nullable", "metadata"}),
        #"Added Custom" = Table.AddColumn(#"Expanded fields1", "isPartitionedBy", each List.Contains([partitionColumns], [name]), Logical.Type),
        #"Buffered Fields" = Table.Buffer(#"Added Custom"),
        #"Added Custom1" = Table.AddColumn(#"Buffered Fields", "PBI_DataType", each if [type] = "long" then Int64.Type
    else if [type] = "integer" then Int32.Type
    else if [type] = "short" then Int16.Type
    else if [type] = "byte" then Int8.Type
    else if [type] = "float" then Single.Type
    else if [type] = "double" then Double.Type
    else if [type] = "string" then Text.Type
    else if [type] = "timestamp" then DateTime.Type
    else if [type] = "boolean" then Logical.Type
    else Text.Type),
        #"Added Custom2" = Table.AddColumn(#"Added Custom1", "ChangeDataType", each {[name], [PBI_DataType]})
    in
        #"Added Custom2",

    #"Data" = 
    let
        Source = #"Logs ALL",
        #"Added Counter" = Table.AddColumn(Source, "Counter", each if [remove] <> null then -1 else if [add] <> null then 1 else null, Int8.Type),
        #"Added file_name" = Table.AddColumn(#"Added Counter", "file_name", each if [add] <> null then Record.Field([add], "path") else if [remove] <> null then Record.Field([remove], "path") else null, Text.Type),
        #"Filtered Rows" = Table.SelectRows(#"Added file_name", each ([file_name] <> null)),
        #"Added partitionValuesTable" = Table.AddColumn(#"Filtered Rows", "partitionValuesTable", each if [add] <> null then if Value.Is(Record.Field([add], "partitionValues"), Record.Type) then Record.ToTable(Record.Field([add], "partitionValues")) else Table.RenameColumns(Record.Field([add], "partitionValues"), {"Key", "Name"}) else null, type nullable table),
        #"Added Custom3" = Table.AddColumn(#"Added partitionValuesTable", "partitionValuesJSON", each Text.FromBinary(Json.FromValue([partitionValuesTable]))),
        #"Grouped Rows1" = Table.Group(#"Added Custom3", {"file_name"}, {{"partitionValuesJSON", each List.Max([partitionValuesJSON]), type nullable text}, {"isRelevant", each List.Sum([Counter]), type nullable text}}),
        #"Relevant Files" = Table.SelectRows(#"Grouped Rows1", each ([isRelevant] > 0)),
        #"Added Custom2" = Table.AddColumn(#"Relevant Files", "partitionValuesTable", each try Table.FromRecords(Json.Document([partitionValuesJSON])) otherwise null, type nullable table),
        #"Added Custom4" = Table.AddColumn(#"Added Custom2", "partitionValues", each try Table.Pivot([partitionValuesTable], Table.SelectRows(#"metadata_columns", each [isPartitionedBy] = true)[name], "Name", "Value") otherwise null, type nullable table),
        #"Expanded partitionValues" = Table.ExpandTableColumn(#"Added Custom4", "partitionValues", Table.SelectRows(#"metadata_columns", each [isPartitionedBy] = true)[name]),
        #"Added Full_Path" = Table.AddColumn(#"Expanded partitionValues", "Full_Path", each Text.Replace(DeltaTablePath & Text.Replace([file_name], "=", "%3D"), "/", Delimiter), Text.Type),
        #"Removed Columns3" = Table.RemoveColumns(#"Added Full_Path",{"file_name", "partitionValuesJSON", "isRelevant", "partitionValuesTable"}),
        #"Buffered RelevantFiles" = Table.Buffer(#"Removed Columns3"),
        #"Merged Queries" = Table.NestedJoin(#"Buffered RelevantFiles", {"Full_Path"}, DeltaTableFolderContent_wFullPath, {"Full_Path"}, "DeltaTable Folder", JoinKind.Inner),
        #"Removed Columns" = Table.RemoveColumns(#"Merged Queries",{"Full_Path"}),
        #"Expanded DeltaTable Folder" = Table.ExpandTableColumn(#"Removed Columns", "DeltaTable Folder", {"Content"}, {"Content"}),
        #"Added Custom1" = Table.AddColumn(#"Expanded DeltaTable Folder", "Data", each Parquet.Document([Content]), Table.Type),
        #"Removed Columns1" = Table.RemoveColumns(#"Added Custom1",{"Content"}),
        #"Expanded Data" = Table.ExpandTableColumn(#"Removed Columns1", "Data", Table.SelectRows(metadata_columns, each not [isPartitionedBy])[name]),
        #"Changed Type" = Table.TransformColumnTypes(#"Expanded Data",metadata_columns[ChangeDataType])
    in
        #"Changed Type"

in #"Data"