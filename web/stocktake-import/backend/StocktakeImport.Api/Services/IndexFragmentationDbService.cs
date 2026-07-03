using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using StocktakeImport.Api.Models;

namespace StocktakeImport.Api.Services;

public interface IIndexFragmentationDbService
{
    Task<IndexFragmentationQueryResult> QueryAsync(
        decimal minFragmentationPercent,
        CancellationToken cancellationToken = default);
}

public class IndexFragmentationDbService : IIndexFragmentationDbService
{
    private readonly string _connectionString;

    public IndexFragmentationDbService(IConfiguration configuration)
    {
        _connectionString = configuration.GetConnectionString("MesDatabase")
            ?? throw new InvalidOperationException("未配置数据库连接字符串 ConnectionStrings:MesDatabase");
    }

    /// <summary>
    /// 调用存储过程 Batch_QueryIndexFragmentation，查询高碎片索引
    /// </summary>
    public async Task<IndexFragmentationQueryResult> QueryAsync(
        decimal minFragmentationPercent,
        CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        var rows = (await connection.QueryAsync<IndexFragmentationRow>(
            new CommandDefinition(
                "dbo.Batch_QueryIndexFragmentation",
                new { MinFragmentationPercent = minFragmentationPercent },
                commandType: CommandType.StoredProcedure,
                cancellationToken: cancellationToken))).ToList();

        return new IndexFragmentationQueryResult
        {
            MinFragmentationPercent = minFragmentationPercent,
            TotalCount = rows.Count,
            Rows = rows
        };
    }
}
