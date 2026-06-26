using ClosedXML.Excel;
using StocktakeImport.Api.Models;

namespace StocktakeImport.Api.Services;

public interface IStocktakeExcelService
{
    ParseExcelResult Parse(Stream stream);
    byte[] CreateTemplate();
}

public class StocktakeExcelService : IStocktakeExcelService
{
    private static readonly string[] RequiredHeaders =
    [
        "工厂", "仓库", "物料号", "库存数量", "单位", "SAP批号"
    ];

    private const string FrozenQtyHeader = "冻结数量";

    private static readonly string[] OptionalLotSnHeaders =
    [
        "批号", "MES批号", "批号/MES批号", "批号 / MES批号"
    ];

    /// <summary>
    /// 解析盘点 Excel，按模板列名读取并校验必填项
    /// </summary>
    public ParseExcelResult Parse(Stream stream)
    {
        var result = new ParseExcelResult();

        using var workbook = new XLWorkbook(stream);
        var sheet = workbook.Worksheets.FirstOrDefault();
        if (sheet is null)
        {
            result.Errors.Add("Excel 中没有工作表");
            return result;
        }

        var headerRow = sheet.FirstRowUsed();
        if (headerRow is null)
        {
            result.Errors.Add("Excel 内容为空");
            return result;
        }

        var columnMap = BuildColumnMap(headerRow);
        var missingHeaders = RequiredHeaders.Where(h => !columnMap.ContainsKey(h)).ToList();
        if (missingHeaders.Count > 0)
        {
            result.Errors.Add($"缺少必填列：{string.Join("、", missingHeaders)}");
            return result;
        }

        var lastRowNumber = sheet.LastRowUsed()?.RowNumber() ?? headerRow.RowNumber();
        for (var rowIndex = headerRow.RowNumber() + 1; rowIndex <= lastRowNumber; rowIndex++)
        {
            var row = sheet.Row(rowIndex);
            if (IsEmptyRow(row, columnMap))
            {
                continue;
            }

            var stocktakeRow = new StocktakeRow
            {
                RowNo = rowIndex,
                FactoryName = GetCellText(row, columnMap["工厂"]),
                WarehouseName = GetCellText(row, columnMap["仓库"]),
                ProductNo = GetCellText(row, columnMap["物料号"]),
                UOMName = GetCellText(row, columnMap["单位"]),
                SAPBatchNo = GetCellText(row, columnMap["SAP批号"])
            };

            var qtyText = GetCellText(row, columnMap["库存数量"]);
            if (!decimal.TryParse(qtyText, out var qty))
            {
                result.Errors.Add($"第 {rowIndex} 行：库存数量「{qtyText}」不是有效数字");
                continue;
            }

            if (qty < 0)
            {
                result.Errors.Add($"第 {rowIndex} 行：库存数量不能小于 0");
                continue;
            }

            stocktakeRow.StockQty = qty;

            // 【冻结数量】可选列，缺省或留空视为 0
            if (columnMap.TryGetValue(FrozenQtyHeader, out var frozenQtyColumn))
            {
                var frozenQtyText = GetCellText(row, frozenQtyColumn);
                if (!string.IsNullOrWhiteSpace(frozenQtyText))
                {
                    if (!decimal.TryParse(frozenQtyText, out var frozenQty))
                    {
                        result.Errors.Add($"第 {rowIndex} 行：冻结数量「{frozenQtyText}」不是有效数字");
                        continue;
                    }

                    if (frozenQty < 0)
                    {
                        result.Errors.Add($"第 {rowIndex} 行：冻结数量不能小于 0");
                        continue;
                    }

                    stocktakeRow.FrozenQty = frozenQty;
                }
            }

            var lotSnColumn = OptionalLotSnHeaders.FirstOrDefault(columnMap.ContainsKey);
            if (lotSnColumn is not null)
            {
                stocktakeRow.LotSN = NullIfEmpty(GetCellText(row, columnMap[lotSnColumn]));
            }

            if (string.IsNullOrWhiteSpace(stocktakeRow.FactoryName) ||
                string.IsNullOrWhiteSpace(stocktakeRow.WarehouseName) ||
                string.IsNullOrWhiteSpace(stocktakeRow.ProductNo) ||
                string.IsNullOrWhiteSpace(stocktakeRow.UOMName) ||
                string.IsNullOrWhiteSpace(stocktakeRow.SAPBatchNo))
            {
                result.Errors.Add($"第 {rowIndex} 行：工厂、仓库、物料号、单位、SAP批号均不能为空");
                continue;
            }

            result.Rows.Add(stocktakeRow);
        }

        result.TotalRows = result.Rows.Count;
        if (result.TotalRows == 0 && result.Errors.Count == 0)
        {
            result.Errors.Add("未读取到有效盘点数据，请检查 Excel 是否有数据行");
        }

        return result;
    }

    /// <summary>
    /// 生成标准盘点 Excel 模板
    /// </summary>
    public byte[] CreateTemplate()
    {
        using var workbook = new XLWorkbook();
        var sheet = workbook.AddWorksheet("盘点数据");

        var headers = new[] { "工厂", "仓库", "物料号", "库存数量", "冻结数量", "单位", "SAP批号", "批号 / MES批号" };
        for (var i = 0; i < headers.Length; i++)
        {
            sheet.Cell(1, i + 1).Value = headers[i];
            sheet.Cell(1, i + 1).Style.Font.Bold = true;
            sheet.Cell(1, i + 1).Style.Fill.BackgroundColor = XLColor.LightGray;
        }

        sheet.Cell(2, 1).Value = "一厂";
        sheet.Cell(2, 2).Value = "原材料仓";
        sheet.Cell(2, 3).Value = "RM001";
        sheet.Cell(2, 4).Value = 100m;
        sheet.Cell(2, 5).Value = 0m;
        sheet.Cell(2, 6).Value = "KG";
        sheet.Cell(2, 7).Value = "SAPBATCH001";

        sheet.Cell(3, 1).Value = "一厂";
        sheet.Cell(3, 2).Value = "原材料仓";
        sheet.Cell(3, 3).Value = "RM002";
        sheet.Cell(3, 4).Value = 50.5m;
        sheet.Cell(3, 5).Value = 10m;
        sheet.Cell(3, 6).Value = "PCS";
        sheet.Cell(3, 7).Value = "SAPBATCH002";

        sheet.Columns().AdjustToContents();

        using var ms = new MemoryStream();
        workbook.SaveAs(ms);
        return ms.ToArray();
    }

    private static Dictionary<string, int> BuildColumnMap(IXLRow headerRow)
    {
        var map = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        foreach (var cell in headerRow.CellsUsed())
        {
            var name = cell.GetString().Trim();
            if (string.IsNullOrEmpty(name))
            {
                continue;
            }

            map.TryAdd(name, cell.Address.ColumnNumber);
        }

        return map;
    }

    private static bool IsEmptyRow(IXLRow row, Dictionary<string, int> columnMap)
    {
        return RequiredHeaders.All(header =>
        {
            var text = GetCellText(row, columnMap[header]);
            return string.IsNullOrWhiteSpace(text);
        });
    }

    private static string GetCellText(IXLRow row, int columnNumber)
    {
        var cell = row.Cell(columnNumber);
        if (cell.IsEmpty())
        {
            return string.Empty;
        }

        if (cell.DataType == XLDataType.Number)
        {
            return cell.GetDouble().ToString(System.Globalization.CultureInfo.InvariantCulture);
        }

        return cell.GetString().Trim();
    }

    private static string? NullIfEmpty(string value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
