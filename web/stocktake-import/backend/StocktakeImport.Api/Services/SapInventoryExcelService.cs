using System.Globalization;
using ClosedXML.Excel;
using StocktakeImport.Api.Models;

namespace StocktakeImport.Api.Services;

public interface ISapInventoryExcelService
{
    SapInventoryParseResult Parse(Stream stream);
    byte[] CreateTemplate();
}

public class SapInventoryExcelService : ISapInventoryExcelService
{
    private static readonly string[] RequiredHeaders =
    [
        "工厂", "仓库", "物料", "批号"
    ];

    // 字段长度上限，对应 SAP_PRODUCT_INVENTORY 表结构
    private const int MaxFactoryName = 10;
    private const int MaxWorkcenterName = 4;
    private const int MaxProductName = 18;
    private const int MaxLotSN = 10;
    private const int MaxUomName = 3;
    private const int MaxStorageDate = 30;
    private const int MaxNote = 30;

    /// <summary>
    /// 解析半成品盘点 Excel，按模板列名读取并校验必填项与字段长度
    /// </summary>
    public SapInventoryParseResult Parse(Stream stream)
    {
        var result = new SapInventoryParseResult();

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

            var item = new SapInventoryRow
            {
                RowNo = rowIndex,
                FactoryName = GetCellText(row, columnMap["工厂"]),
                WorkcenterName = GetCellText(row, columnMap["仓库"]),
                ProductName = GetCellText(row, columnMap["物料"]),
                LotSN = GetCellText(row, columnMap["批号"]),
                UomName = GetOptionalText(row, columnMap, "单位"),
                StorageDate = GetOptionalText(row, columnMap, "入库日期"),
                Note = GetOptionalText(row, columnMap, "备注")
            };

            // 【必填校验】工厂、仓库、物料、批号不能为空
            if (string.IsNullOrWhiteSpace(item.FactoryName) ||
                string.IsNullOrWhiteSpace(item.WorkcenterName) ||
                string.IsNullOrWhiteSpace(item.ProductName) ||
                string.IsNullOrWhiteSpace(item.LotSN))
            {
                result.Errors.Add($"第 {rowIndex} 行：工厂、仓库、物料、批号均不能为空");
                continue;
            }

            // 【数量解析】三个数量列可空，但至少有一列有值
            if (!TryParseQty(row, columnMap, "在库数量", rowIndex, result, out var inventoryNum) ||
                !TryParseQty(row, columnMap, "质检数量", rowIndex, result, out var checkNum) ||
                !TryParseQty(row, columnMap, "锁定数量", rowIndex, result, out var lockQty))
            {
                continue;
            }

            if (inventoryNum is null && checkNum is null && lockQty is null)
            {
                result.Errors.Add($"第 {rowIndex} 行：在库数量、质检数量、锁定数量至少填写一项");
                continue;
            }

            item.ProductInventoryNum = inventoryNum;
            item.CheckNum = checkNum;
            item.LockQty = lockQty;

            // 【长度校验】超出目标表字段长度时报错并返回行号
            var lengthError = CheckLength(item);
            if (lengthError is not null)
            {
                result.Errors.Add($"第 {rowIndex} 行：{lengthError}");
                continue;
            }

            result.Rows.Add(item);
        }

        result.TotalRows = result.Rows.Count;
        if (result.TotalRows == 0 && result.Errors.Count == 0)
        {
            result.Errors.Add("未读取到有效数据，请检查 Excel 是否有数据行");
        }

        return result;
    }

    /// <summary>
    /// 生成标准半成品盘点 Excel 模板
    /// </summary>
    public byte[] CreateTemplate()
    {
        using var workbook = new XLWorkbook();
        var sheet = workbook.AddWorksheet("半成品盘点");

        var headers = new[] { "工厂", "仓库", "物料", "批号", "在库数量", "质检数量", "锁定数量", "单位", "入库日期", "备注" };
        for (var i = 0; i < headers.Length; i++)
        {
            sheet.Cell(1, i + 1).Value = headers[i];
            sheet.Cell(1, i + 1).Style.Font.Bold = true;
            sheet.Cell(1, i + 1).Style.Fill.BackgroundColor = XLColor.LightGray;
        }

        sheet.Cell(2, 1).Value = "一厂";
        sheet.Cell(2, 2).Value = "半成品仓";
        sheet.Cell(2, 3).Value = "SF001";
        sheet.Cell(2, 4).Value = "LOT001";
        sheet.Cell(2, 5).Value = 100m;
        sheet.Cell(2, 8).Value = "KG";
        sheet.Cell(2, 9).Value = "2026-06-01";

        sheet.Columns().AdjustToContents();

        using var ms = new MemoryStream();
        workbook.SaveAs(ms);
        return ms.ToArray();
    }

    private static string? CheckLength(SapInventoryRow item)
    {
        if (item.FactoryName.Length > MaxFactoryName)
        {
            return $"工厂名称超过 {MaxFactoryName} 个字符";
        }

        if (item.WorkcenterName.Length > MaxWorkcenterName)
        {
            return $"仓库名称超过 {MaxWorkcenterName} 个字符";
        }

        if (item.ProductName.Length > MaxProductName)
        {
            return $"物料名称超过 {MaxProductName} 个字符";
        }

        if (item.LotSN.Length > MaxLotSN)
        {
            return $"批号超过 {MaxLotSN} 个字符";
        }

        if ((item.UomName?.Length ?? 0) > MaxUomName)
        {
            return $"单位超过 {MaxUomName} 个字符";
        }

        if ((item.StorageDate?.Length ?? 0) > MaxStorageDate)
        {
            return $"入库日期超过 {MaxStorageDate} 个字符";
        }

        if ((item.Note?.Length ?? 0) > MaxNote)
        {
            return $"备注超过 {MaxNote} 个字符";
        }

        return null;
    }

    private static bool TryParseQty(
        IXLRow row,
        Dictionary<string, int> columnMap,
        string header,
        int rowIndex,
        SapInventoryParseResult result,
        out decimal? value)
    {
        value = null;
        if (!columnMap.TryGetValue(header, out var column))
        {
            return true;
        }

        var text = GetCellText(row, column);
        if (string.IsNullOrWhiteSpace(text))
        {
            return true;
        }

        if (!decimal.TryParse(text, NumberStyles.Any, CultureInfo.InvariantCulture, out var qty))
        {
            result.Errors.Add($"第 {rowIndex} 行：{header}「{text}」不是有效数字");
            return false;
        }

        if (qty < 0)
        {
            result.Errors.Add($"第 {rowIndex} 行：{header}不能小于 0");
            return false;
        }

        value = qty;
        return true;
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

    private static string? GetOptionalText(IXLRow row, Dictionary<string, int> columnMap, string header)
    {
        if (!columnMap.TryGetValue(header, out var column))
        {
            return null;
        }

        var text = GetCellText(row, column);
        return string.IsNullOrWhiteSpace(text) ? null : text;
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
            return cell.GetDouble().ToString(CultureInfo.InvariantCulture);
        }

        if (cell.DataType == XLDataType.DateTime)
        {
            return cell.GetDateTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        }

        return cell.GetString().Trim();
    }
}
