using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using StocktakeImport.Api.Models;

namespace StocktakeImport.Api.Services;

public record DatabaseConnectionInfo(string DatabaseName, string EnvironmentLabel);

public interface IStocktakeDbService
{
    DatabaseConnectionInfo GetConnectionInfo();
    Task<bool> TestConnectionAsync(CancellationToken cancellationToken = default);
    Task<int> ImportStocktakeDataAsync(
        IReadOnlyList<StocktakeRow> rows,
        string createUserId,
        CancellationToken cancellationToken = default);
    Task<string> ExecuteStocktakeUpdateAsync(
        string createUserId,
        bool dryRun,
        CancellationToken cancellationToken = default);
}

public class StocktakeDbService : IStocktakeDbService
{
    private readonly string _connectionString;
    private readonly DatabaseConnectionInfo _connectionInfo;

    public StocktakeDbService(IConfiguration configuration, IWebHostEnvironment environment)
    {
        _connectionString = configuration.GetConnectionString("MesDatabase")
            ?? throw new InvalidOperationException("未配置数据库连接字符串 ConnectionStrings:MesDatabase");

        var builder = new SqlConnectionStringBuilder(_connectionString);
        var databaseName = string.IsNullOrWhiteSpace(builder.InitialCatalog)
            ? "未知数据库"
            : builder.InitialCatalog;

        var environmentLabel = environment.IsProduction() ? "生产环境" : "测试环境";
        _connectionInfo = new DatabaseConnectionInfo(databaseName, environmentLabel);
    }

    /// <summary>
    /// 获取当前连接的数据库与环境信息
    /// </summary>
    public DatabaseConnectionInfo GetConnectionInfo() => _connectionInfo;

    /// <summary>
    /// 测试数据库连接是否可用
    /// </summary>
    public async Task<bool> TestConnectionAsync(CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        var result = await connection.ExecuteScalarAsync<int>(
            new CommandDefinition("SELECT 1", cancellationToken: cancellationToken));
        return result == 1;
    }

    /// <summary>
    /// 清空并写入 TempStocktakeData 暂存表
    /// </summary>
    public async Task<int> ImportStocktakeDataAsync(
        IReadOnlyList<StocktakeRow> rows,
        string createUserId,
        CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        var trimmedUserId = string.IsNullOrWhiteSpace(createUserId)
            ? null
            : createUserId.Trim();

        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        try
        {
            // 【清空暂存表】每次导入前先清理上次数据
            await connection.ExecuteAsync(
                new CommandDefinition(
                    "DELETE FROM dbo.TempStocktakeData",
                    transaction: transaction,
                    cancellationToken: cancellationToken));

            // 【写入盘点数据】使用参数化插入，避免 SQL 注入
            const string insertSql = """
                INSERT INTO dbo.TempStocktakeData
                (
                    RowNo, FactoryName, WarehouseName, ProductNo,
                    StockQty, FrozenQty, UOMName, SAPBatchNo, LotSN, CreateUserId
                )
                VALUES
                (
                    @RowNo, @FactoryName, @WarehouseName, @ProductNo,
                    @StockQty, @FrozenQty, @UOMName, @SAPBatchNo, @LotSN, @CreateUserId
                );
                """;

            foreach (var row in rows)
            {
                await connection.ExecuteAsync(
                    new CommandDefinition(
                        insertSql,
                        new
                        {
                            row.RowNo,
                            FactoryName = row.FactoryName.Trim(),
                            WarehouseName = row.WarehouseName.Trim(),
                            ProductNo = row.ProductNo.Trim(),
                            row.StockQty,
                            row.FrozenQty,
                            UOMName = row.UOMName.Trim(),
                            SAPBatchNo = row.SAPBatchNo.Trim(),
                            LotSN = string.IsNullOrWhiteSpace(row.LotSN) ? null : row.LotSN.Trim(),
                            CreateUserId = trimmedUserId
                        },
                        transaction: transaction,
                        cancellationToken: cancellationToken));
            }

            await transaction.CommitAsync(cancellationToken);
            return rows.Count;
        }
        catch
        {
            await transaction.RollbackAsync(cancellationToken);
            throw;
        }
    }

    /// <summary>
    /// 调用盘点更新存储过程，从 TempStocktakeData 读取数据
    /// </summary>
    public async Task<string> ExecuteStocktakeUpdateAsync(
        string createUserId,
        bool dryRun,
        CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        var trimmedUserId = string.IsNullOrWhiteSpace(createUserId)
            ? null
            : createUserId.Trim();

        var parameters = new DynamicParameters();
        parameters.Add("@I_ReturnMessage", dbType: DbType.String, size: -1, direction: ParameterDirection.Output);
        parameters.Add("@CreateUserId", trimmedUserId ?? string.Empty);
        parameters.Add("@DryRun", dryRun);

        await connection.ExecuteAsync(
            new CommandDefinition(
                "dbo.Batch_StocktakeUpdateRMInventory",
                parameters,
                commandType: CommandType.StoredProcedure,
                cancellationToken: cancellationToken));

        return parameters.Get<string>("@I_ReturnMessage") ?? "{}";
    }
}
