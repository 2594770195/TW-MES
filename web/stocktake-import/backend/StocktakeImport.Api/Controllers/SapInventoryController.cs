using Microsoft.AspNetCore.Mvc;
using StocktakeImport.Api.Models;
using StocktakeImport.Api.Services;

namespace StocktakeImport.Api.Controllers;

[ApiController]
[Route("api/sap-inventory")]
public class SapInventoryController : ControllerBase
{
    private readonly ISapInventoryExcelService _excelService;
    private readonly ISapInventoryDbService _dbService;
    private readonly ILogger<SapInventoryController> _logger;

    public SapInventoryController(
        ISapInventoryExcelService excelService,
        ISapInventoryDbService dbService,
        ILogger<SapInventoryController> logger)
    {
        _excelService = excelService;
        _dbService = dbService;
        _logger = logger;
    }

    /// <summary>
    /// 下载半成品盘点 Excel 模板
    /// </summary>
    [HttpGet("template")]
    public IActionResult DownloadTemplate()
    {
        var bytes = _excelService.CreateTemplate();
        return File(
            bytes,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "半成品盘点导入模板.xlsx");
    }

    /// <summary>
    /// 上传 Excel 并写入 SAP_PRODUCT_INVENTORY
    /// </summary>
    [HttpPost("import")]
    [RequestSizeLimit(20 * 1024 * 1024)]
    public async Task<ActionResult<ApiResponse<SapInventoryParseResult>>> ImportExcel(
        IFormFile? file,
        CancellationToken cancellationToken)
    {
        if (file is null || file.Length == 0)
        {
            return Ok(ApiResponse<SapInventoryParseResult>.Fail("请上传 Excel 文件"));
        }

        var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (extension is not ".xlsx" and not ".xlsm")
        {
            return Ok(ApiResponse<SapInventoryParseResult>.Fail("仅支持 .xlsx 或 .xlsm 格式"));
        }

        try
        {
            using var stream = file.OpenReadStream();
            var parsed = _excelService.Parse(stream);

            if (parsed.Errors.Count > 0)
            {
                return Ok(new ApiResponse<SapInventoryParseResult>
                {
                    Code = 1,
                    Message = $"Excel 导入失败，共 {parsed.Errors.Count} 个问题",
                    Data = parsed
                });
            }

            var importedRows = await _dbService.ImportSapInventoryAsync(parsed.Rows, cancellationToken);
            parsed.TotalRows = importedRows;
            return Ok(ApiResponse<SapInventoryParseResult>.Ok(
                parsed,
                $"成功导入 {importedRows} 行数据到 SAP_PRODUCT_INVENTORY"));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "导入半成品 Excel 失败");
            return Ok(ApiResponse<SapInventoryParseResult>.Fail("导入 Excel 时发生错误，请确认文件格式和数据库表结构"));
        }
    }

    /// <summary>
    /// 按工厂 + 仓库执行半成品盘点（调用 UpdateInventoryBySAP_BCP）
    /// </summary>
    [HttpPost("execute")]
    public async Task<ActionResult<ApiResponse<ExecuteSapInventoryResult>>> Execute(
        [FromBody] ExecuteSapInventoryRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.FactoryName) ||
            string.IsNullOrWhiteSpace(request.WarehouseName))
        {
            return Ok(ApiResponse<ExecuteSapInventoryResult>.Fail("请填写工厂和仓库"));
        }

        try
        {
            // 【预检】存储过程对“找不到仓库”仅返回提示而不中止，应用层先校验，校验失败不调用存储过程
            var exists = await _dbService.WarehouseExistsAsync(
                request.FactoryName,
                request.WarehouseName,
                cancellationToken);

            if (!exists)
            {
                return Ok(ApiResponse<ExecuteSapInventoryResult>.Fail("找不到仓库，请检查工厂和仓库名称是否正确"));
            }

            await _dbService.ExecuteSapInventoryUpdateAsync(
                request.FactoryName,
                request.WarehouseName,
                cancellationToken);

            var result = new ExecuteSapInventoryResult
            {
                FactoryName = request.FactoryName.Trim(),
                WarehouseName = request.WarehouseName.Trim()
            };

            return Ok(ApiResponse<ExecuteSapInventoryResult>.Ok(result, "半成品盘点执行完成"));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "执行半成品盘点存储过程失败");
            return Ok(ApiResponse<ExecuteSapInventoryResult>.Fail("执行盘点更新失败，请稍后重试或联系管理员"));
        }
    }
}
