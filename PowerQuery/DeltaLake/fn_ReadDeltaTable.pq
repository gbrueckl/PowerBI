(
    DeltaTableFolderContent as table,
    optional DeltaTableOptions as record
) as table =>

let

    DeltaTableVersion = if DeltaTableOptions = null or not Record.HasFields(DeltaTableOptions, "Version") then null else Record.Field(DeltaTableOptions, "Version"),

    #"Delimiter" = 
    let
        DeltaTablePath = Text.End(DeltaTableFolderContent{0}[Folder Path], 1)
    in
        DeltaTablePath,

    #"_delta_log Folder" = 
    let
       Source = DeltaTableFolderContent,
       #"Filtered Rows" = Table.SelectRows(Source, each Text.EndsWith([Folder Path], Delimiter & "_delta_log" & Delimiter)),
       #"Added Version" = Table.AddColumn(#"Filtered Rows", "Version", each try Int64.From(Text.BeforeDelimiter([Name], ".")) otherwise -1, Int64.Type),
       #"Filtered RequestedVersion" = if DeltaTableVersion = null then #"Added Version" else Table.SelectRows(#"Added Version", each [Version] <= DeltaTableVersion),
       buffered = Table.Buffer(#"Filtered RequestedVersion")
    in
        buffered,

    #"DeltaTablePath" = 
    let
        DeltaTablePath = Text.Replace(#"_delta_log Folder"{0}[Folder Path], "_delta_log" & Delimiter, "")
    in
        DeltaTablePath,

    #"_last_checkpoint" = 
    let
        #"_delta_log" = #"_delta_log Folder",
        #"Filtered Rows" = Table.SelectRows(_delta_log, each [Name] = "_last_checkpoint"),
        #"Added Custom" = Table.AddColumn(#"Filtered Rows", "JsonContent", each Json.Document([Content])),
        JsonContent = #"Added Custom"{[#"Folder Path"=DeltaTablePath & "_delta_log" & Delimiter,Name="_last_checkpoint"]}[JsonContent],
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
        Content = Table.SelectRows(#"_delta_log Folder", each List.Contains(Table.ToList(AllFiles), [Name]))
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
        #"Added Counter" = Table.AddColumn(Source, "Counter", each if [remove] <> null then -1 else if [add] <> null then 1 else null, Int8.Type),
        #"Expanded remove" = Table.ExpandRecordColumn(#"Added Counter", "remove", {"path"}, {"remove.path"}),
        #"Expanded add" = Table.ExpandRecordColumn(#"Expanded remove", "add", {"path"}, {"add.path"}),
        #"Added Custom1" = Table.AddColumn(#"Expanded add", "file_name_delta", each if [Counter] = -1 then [remove.path] else [add.path], Text.Type),
        buffered = Table.Buffer(#"Added Custom1")
    in
        buffered,

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
        #"Grouped Rows" = Table.Group(Source, {"file_name_delta"}, {{"isRelevant", each List.Sum([Counter]), Int8.Type}}),
        #"Relevant Files" = Table.SelectRows(#"Grouped Rows", each ([isRelevant] > 0)),
        #"Added full_path" = Table.AddColumn(#"Relevant Files", "full_path", each DeltaTablePath & Text.Replace([file_name_delta], "=", "%3D"), Text.Type),
        #"Split Column by Delimiter" = Table.SplitColumn(#"Added full_path", "full_path", Splitter.SplitTextByEachDelimiter({Delimiter}, QuoteStyle.Csv, true), {"FolderPath", "Name"}),
        #"Added Custom" = Table.AddColumn(#"Split Column by Delimiter", "Folder Path", each [FolderPath] & Delimiter, Text.Type),
        #"Removed Other Columns" = Table.SelectColumns(#"Added Custom",{"Folder Path", "Name"}),
        #"Split PartitionFolders" = Table.AddColumn(#"Removed Other Columns", "PartitionFolders", each Text.Trim(Text.Replace([Folder Path], DeltaTablePath, ""), Delimiter), Text.Type),
        #"Split PartitionColumns" = Table.AddColumn(#"Split PartitionFolders", "PartitionList", each Text.Split([PartitionFolders], Delimiter)),
        #"Get PartitionValues" = Table.TransformColumns(#"Split PartitionColumns", {"PartitionList", (x) => Table.FromRecords(List.Transform(x, (y) => Record.FromList(Text.Split(y, "%3D"), {"Column", "Value"})))}),
        #"Pivot PartitionValues" = Table.AddColumn(#"Get PartitionValues", "PartitionValues", each Table.Pivot([PartitionList], List.Distinct([PartitionList][Column]), "Column", "Value", List.Max)),
        #"Expanded PartitionValues" = Table.ExpandTableColumn(#"Pivot PartitionValues", "PartitionValues", Table.SelectRows(metadata_columns, each [isPartitionedBy])[name]),
        #"Buffered RelevantFiles" = Table.Buffer(#"Expanded PartitionValues"),
        #"Merged Queries" = Table.NestedJoin(#"Buffered RelevantFiles", {"Folder Path", "Name"}, DeltaTableFolderContent, {"Folder Path", "Name"}, "DeltaTable Folder", JoinKind.Inner),
        #"Removed Columns" = Table.RemoveColumns(#"Merged Queries",{"Folder Path", "Name", "PartitionFolders", "PartitionList"}),
        #"Expanded DeltaTable Folder" = Table.ExpandTableColumn(#"Removed Columns", "DeltaTable Folder", {"Content", "Folder Path"}, {"Content", "Folder Path"}),
        #"Added Custom1" = Table.AddColumn(#"Expanded DeltaTable Folder", "Data", each Parquet.Document([Content]), Table.Type),
        #"Removed Columns1" = Table.RemoveColumns(#"Added Custom1",{"Content", "Folder Path"}),
        #"Expanded Data" = Table.ExpandTableColumn(#"Removed Columns1", "Data", Table.SelectRows(metadata_columns, each not [isPartitionedBy])[name]),
        #"Changed Type" = Table.TransformColumnTypes(#"Expanded Data",metadata_columns[ChangeDataType])
    in
        #"Changed Type"

in #"Data"