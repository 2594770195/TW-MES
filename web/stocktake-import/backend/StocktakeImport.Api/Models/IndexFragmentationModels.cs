namespace StocktakeImport.Api.Models;

public class IndexFragmentationRow
{
    public string SchemaName { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public string IndexName { get; set; } = string.Empty;
    public decimal FragmentationPercent { get; set; }
}

public class IndexFragmentationQueryResult
{
    public decimal MinFragmentationPercent { get; set; }
    public int TotalCount { get; set; }
    public List<IndexFragmentationRow> Rows { get; set; } = [];
}
