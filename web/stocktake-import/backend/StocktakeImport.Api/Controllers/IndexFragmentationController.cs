using Microsoft.AspNetCore.Mvc;
using StocktakeImport.Api.Models;
using StocktakeImport.Api.Services;

namespace StocktakeImport.Api.Controllers;

[ApiController]
[Route("api/index-fragmentation")]
public class IndexFragmentationController : ControllerBase
{
    private readonly IIndexFragmentationDbService _dbService;
    private readonly ILogger<IndexFragmentationController> _logger;

    public IndexFragmentationController(
        IIndexFragmentationDbService dbService,
        ILogger<IndexFragmentationController> logger)
    {
        _dbService = dbService;
        _logger = logger;
    }

    /// <summary>
    /// 查询碎片率超过阈值的表及索引
    /// </summary>
    [HttpGet("query")]
    public async Task<ActionResult<ApiResponse<IndexFragmentationQueryResult>>> Query(
        [FromQuery] decimal minPercent = 80,
        CancellationToken cancellationToken = default)
    {
        if (minPercent is < 0 or > 100)
        {
            return Ok(ApiResponse<IndexFragmentationQueryResult>.Fail("碎片百分比阈值须在 0～100 之间"));
        }

        try
        {
            var result = await _dbService.QueryAsync(minPercent, cancellationToken);
            var message = result.TotalCount > 0
                ? $"共发现 {result.TotalCount} 个碎片率超过 {minPercent}% 的索引"
                : $"未发现碎片率超过 {minPercent}% 的索引";

            return Ok(ApiResponse<IndexFragmentationQueryResult>.Ok(result, message));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "查询索引碎片失败");
            return Ok(ApiResponse<IndexFragmentationQueryResult>.Fail(
                "查询索引碎片失败，请确认已部署存储过程 dbo.Batch_QueryIndexFragmentation"));
        }
    }
}
