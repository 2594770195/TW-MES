namespace StocktakeImport.Api.Models;

/// <summary>
/// 盘点 Excel 单行数据，对应暂存表 TempStocktakeData
/// </summary>
public class StocktakeRow
{
    public int RowNo { get; set; }
    public string FactoryName { get; set; } = string.Empty;
    public string WarehouseName { get; set; } = string.Empty;
    public string ProductNo { get; set; } = string.Empty;
    public decimal StockQty { get; set; }
    public decimal FrozenQty { get; set; }
    public string UOMName { get; set; } = string.Empty;
    public string SAPBatchNo { get; set; } = string.Empty;
    public string? LotSN { get; set; }
}
