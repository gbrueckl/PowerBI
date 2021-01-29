# Reading Delta Lake tables natively in PowerBI
The provided PowerQuery/M function allows you to read a Delta Lake table directly from any storage supported by PowerBI. Most common storages would be Azure Data Lake Store, Azure Blob Storage or a local folder or file share.

# Features
- Read Delta Lake table into PowerBI without having a cluster (Spark, Databricks, Azure Synapse) up and running
- Support all storage systems that are supported by PowerBI
    - Azure Data Lake Store
    - Azure Blob Storage
    - Local Folder or Network Share
- Support for Delta Lake time travel - reading `VERSION AS OF`

# Known limitations
- Reading from Blob Store
    - currently needs some tweaking as file listing returned by  the blob connector is slightly different to e.g. the Azure Data Lake Store connector
- Support for partitioned tables
   - currently columns used for partitioning will always have the value NULL
   - values for partitioning columns are not stored as part of the parquet file but need to be derived from the folder path
- Performance
   - is currently not great but this is mainly related to the Parquet connector as it seems
- Time Travel
   - currently only supports “VERSION AS OF”
   - need to add “TIMESTAMP AS OF”
- Predicate Pushdown / Partition Elimination
   - currently not supported – it always reads the whole table and filters afterwards


# FAQ

Q: How can I read my Delta Lake table stored on Azure Blob Storage?

A: Here is some sample code which returns the expected folder structure form a Blob Storage:
```
let
    Source = AzureStorage.Blobs("https://myaccount.blob.core.windows.net/mycontainer"),
    #"Filtered Rows" = Table.SelectRows(Source, each Text.StartsWith([Name], "myFolder/myDeltaTable")),
    #"Added FullPath" = Table.AddColumn(#"Filtered Rows", "FullPath", each [Folder Path] & "/" & [Name], Text.Type),
    #"Removed Columns" = Table.RemoveColumns(#"Added FullPath",{"Name", "Folder Path"}),
    #"Split Column by Delimiter" = Table.SplitColumn(#"Removed Columns", "FullPath", Splitter.SplitTextByEachDelimiter({"/"}, QuoteStyle.Csv, true), {"Folder Path", "Name"}),
    #"Append Delimiter" = Table.TransformColumns(#"Split Column by Delimiter",{{"Folder Path", (_) => _ & "/", type text}})
in
    #"Append Delimiter"
```
The output can be fed into the function then.