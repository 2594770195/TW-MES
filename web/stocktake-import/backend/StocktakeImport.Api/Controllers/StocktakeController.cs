using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using StocktakeImport.Api.Models;
using StocktakeImport.Api.Services;

namespace StocktakeImport.Api.Controllers;

[ApiController]
[Route("api/stocktake")]
public class StocktakeController : ControllerBase
{
    private readonly IStocktakeExcelService _excelService;
    private readonly IStocktakeDbService _dbService;
    private readonly ILogger<StocktakeController> _logger;

    public StocktakeController(
        IStocktakeExcelService excelService,
        IStocktakeDbService dbService,
        ILogger<StocktakeController> logger)
    {
        _excelService = excelService;
        _dbService = dbService;
        _logger = logger;
    }

    /// <summary>
    /// 检查服务与数据库连接状态
    /// </summary>
    [HttpGet("health")]
    public async Task<ActionResult<ApiResponse<object>>> Health(CancellationToken cancellationToken)
    {
        try
        {
            var ok = await _dbService.TestConnectionAsync(cancellationToken);
            if (!ok)
            {
                return Ok(ApiResponse<object>.Fail("数据库连接失败"));
            }

            var connectionInfo = _dbService.GetConnectionInfo();
            return Ok(ApiResponse<object>.Ok(
                new
                {
                    database = connectionInfo.DatabaseName,
                    environment = connectionInfo.EnvironmentLabel,
                },
                "服务正常"));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "数据库连接检查失败");
            return Ok(ApiResponse<object>.Fail("无法连接数据库，请检查连接配置"));
        }
    }

    /// <summary>
    /// 下载盘点 Excel 模板
    /// </summary>
    [HttpGet("template")]
    public IActionResult DownloadTemplate()
    {
        var bytes = _excelService.CreateTemplate();
        return File(
            bytes,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "库存盘点导入模板.xlsx");
    }

    /// <summary>
    /// 上传 Excel 并写入 TempStocktakeData 暂存表
    /// </summary>
    [HttpPost("import")]
    [RequestSizeLimit(20 * 1024 * 1024)]
    public async Task<ActionResult<ApiResponse<ParseExcelResult>>> ImportExcel(
        IFormFile? file,
        [FromForm] string? createUserId,
        CancellationToken cancellationToken)
    {
        if (file is null || file.Length == 0)
        {
            return Ok(ApiResponse<ParseExcelResult>.Fail("请上传 Excel 文件"));
        }

        var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (extension is not ".xlsx" and not ".xlsm")
        {
            return Ok(ApiResponse<ParseExcelResult>.Fail("仅支持 .xlsx 或 .xlsm 格式"));
        }

        try
        {
            using var stream = file.OpenReadStream();
            var parsed = _excelService.Parse(stream);

            if (parsed.Errors.Count > 0)
            {
                return Ok(new ApiResponse<ParseExcelResult>
                {
                    Code = 1,
                    Message = $"Excel 导入失败，共 {parsed.Errors.Count} 个问题",
                    Data = parsed
                });
            }

            var importedRows = await _dbService.ImportStocktakeDataAsync(
                parsed.Rows,
                createUserId ?? string.Empty,
                cancellationToken);

            parsed.TotalRows = importedRows;
            return Ok(ApiResponse<ParseExcelResult>.Ok(
                parsed,
                $"成功导入 {importedRows} 行盘点数据到 TempStocktakeData"));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "导入 Excel 失败");
            return Ok(ApiResponse<ParseExcelResult>.Fail("导入 Excel 时发生错误，请确认文件格式和数据库表结构"));
        }
    }

    /// <summary>
    /// 执行盘点预览或正式更新（从 TempStocktakeData 读取）
    /// </summary>
    [HttpPost("execute")]
    public async Task<ActionResult<ApiResponse<ExecuteStocktakeResult>>> Execute(
        [FromBody] ExecuteStocktakeRequest request,
        CancellationToken cancellationToken)
    {
        try
        {
            var rawJson = await _dbService.ExecuteStocktakeUpdateAsync(
                request.CreateUserId,
                request.DryRun,
                cancellationToken);

            object? parsed = null;
            try
            {
                parsed = JsonSerializer.Deserialize<object>(rawJson);
            }
            catch
            {
                // 返回原始 JSON 字符串即可
            }

            var result = new ExecuteStocktakeResult
            {
                RawJson = rawJson,
                Parsed = parsed
            };

            var actionText = request.DryRun ? "预览" : "正式更新";
            return Ok(ApiResponse<ExecuteStocktakeResult>.Ok(result, $"{actionText}执行完成"));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "执行盘点存储过程失败");
            return Ok(ApiResponse<ExecuteStocktakeResult>.Fail("执行盘点更新失败，请稍后重试或联系管理员"));
        }
    }
}
