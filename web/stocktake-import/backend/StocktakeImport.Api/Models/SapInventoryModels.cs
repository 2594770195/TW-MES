namespace StocktakeImport.Api.Models;

/// <summary>
/// 半成品盘点 Excel 单行数据，对应表 SAP_PRODUCT_INVENTORY
/// </summary>
public class SapInventoryRow
{
    public int RowNo { get; set; }
    public string FactoryName { get; set; } = string.Empty;
    public string WorkcenterName { get; set; } = string.Empty;
    public string ProductName { get; set; } = string.Empty;
    public string LotSN { get; set; } = string.Empty;
    public decimal? ProductInventoryNum { get; set; }
    public decimal? CheckNum { get; set; }
    public decimal? LockQty { get; set; }
    public string? UomName { get; set; }
    public string? StorageDate { get; set; }
    public string? Note { get; set; }
}

/// <summary>
/// 半成品 Excel 解析结果
/// </summary>
public class SapInventoryParseResult
{
    public List<SapInventoryRow> Rows { get; set; } = [];
    public List<string> Errors { get; set; } = [];
    public int TotalRows { get; set; }
}

/// <summary>
/// 执行半成品盘点请求：按工厂 + 仓库调用存储过程
/// </summary>
public class ExecuteSapInventoryRequest
{
    public string FactoryName { get; set; } = string.Empty;
    public string WarehouseName { get; set; } = string.Empty;
}

/// <summary>
/// 执行半成品盘点结果
/// </summary>
public class ExecuteSapInventoryResult
{
    public string FactoryName { get; set; } = string.Empty;
    public string WarehouseName { get; set; } = string.Empty;
}
