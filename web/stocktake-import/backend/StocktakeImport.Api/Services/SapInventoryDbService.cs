using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using StocktakeImport.Api.Models;

namespace StocktakeImport.Api.Services;

public interface ISapInventoryDbService
{
    Task<int> ImportSapInventoryAsync(
        IReadOnlyList<SapInventoryRow> rows,
        CancellationToken cancellationToken = default);
    Task<bool> WarehouseExistsAsync(
        string factoryName,
        string warehouseName,
        CancellationToken cancellationToken = default);
    Task ExecuteSapInventoryUpdateAsync(
        string factoryName,
        string warehouseName,
        CancellationToken cancellationToken = default);
}

public class SapInventoryDbService : ISapInventoryDbService
{
    private readonly string _connectionString;

    public SapInventoryDbService(IConfiguration configuration)
    {
        _connectionString = configuration.GetConnectionString("MesDatabase")
            ?? throw new InvalidOperationException("未配置数据库连接字符串 ConnectionStrings:MesDatabase");
    }

    /// <summary>
    /// 按工厂+仓库覆盖写入 SAP_PRODUCT_INVENTORY：先按去重的工厂仓库集合删除旧数据，再批量插入
    /// </summary>
    public async Task<int> ImportSapInventoryAsync(
        IReadOnlyList<SapInventoryRow> rows,
        CancellationToken cancellationToken = default)
    {
        if (rows.Count == 0)
        {
            return 0;
        }

        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        try
        {
            // 【清空】按本批数据去重后的工厂+仓库集合统一删除一次，避免逐行先删后插覆盖数据
            var scopes = rows
                .Select(r => new
                {
                    FactoryName = r.FactoryName.Trim(),
                    WorkcenterName = r.WorkcenterName.Trim()
                })
                .Distinct()
                .ToList();

            const string deleteSql = """
                DELETE FROM dbo.SAP_PRODUCT_INVENTORY
                WHERE FactoryName = @FactoryName AND WorkcenterName = @WorkcenterName;
                """;

            foreach (var scope in scopes)
            {
                await connection.ExecuteAsync(
                    new CommandDefinition(
                        deleteSql,
                        scope,
                        transaction: transaction,
                        cancellationToken: cancellationToken));
            }

            // 【写入】参数化批量插入，Id 使用 GUID，isChange 默认 0
            const string insertSql = """
                INSERT INTO dbo.SAP_PRODUCT_INVENTORY
                (
                    Id, FactoryName, WorkcenterName, ProductName, LotSN,
                    ProductInventoryNum, CheckNum, LockQty, UomName, StorageDate, Note, isChange
                )
                VALUES
                (
                    @Id, @FactoryName, @WorkcenterName, @ProductName, @LotSN,
                    @ProductInventoryNum, @CheckNum, @LockQty, @UomName, @StorageDate, @Note, '0'
                );
                """;

            foreach (var row in rows)
            {
                await connection.ExecuteAsync(
                    new CommandDefinition(
                        insertSql,
                        new
                        {
                            Id = Guid.NewGuid().ToString("N"),
                            FactoryName = row.FactoryName.Trim(),
                            WorkcenterName = row.WorkcenterName.Trim(),
                            ProductName = row.ProductName.Trim(),
                            LotSN = row.LotSN.Trim(),
                            row.ProductInventoryNum,
                            row.CheckNum,
                            row.LockQty,
                            UomName = NullIfEmpty(row.UomName),
                            StorageDate = NullIfEmpty(row.StorageDate),
                            Note = NullIfEmpty(row.Note)
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
    /// 调用存储过程前预检：工厂 + 仓库是否存在
    /// </summary>
    public async Task<bool> WarehouseExistsAsync(
        string factoryName,
        string warehouseName,
        CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        const string sql = """
            SELECT TOP 1 1
            FROM dbo.Workcenter wc WITH (NOLOCK)
            INNER JOIN dbo.Factory f WITH (NOLOCK) ON f.FactoryId = wc.FactoryId
            WHERE f.FactoryName = @FactoryName
              AND wc.WorkcenterName = @WarehouseName;
            """;

        var hit = await connection.ExecuteScalarAsync<int?>(
            new CommandDefinition(
                sql,
                new { FactoryName = factoryName.Trim(), WarehouseName = warehouseName.Trim() },
                cancellationToken: cancellationToken));

        return hit == 1;
    }

    /// <summary>
    /// 按工厂 + 仓库调用半成品盘点存储过程 UpdateInventoryBySAP_BCP
    /// </summary>
    public async Task ExecuteSapInventoryUpdateAsync(
        string factoryName,
        string warehouseName,
        CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        var parameters = new DynamicParameters();
        parameters.Add("@WarehouseName", warehouseName.Trim());
        parameters.Add("@FactoryName", factoryName.Trim());

        await connection.ExecuteAsync(
            new CommandDefinition(
                "dbo.UpdateInventoryBySAP_BCP",
                parameters,
                commandType: CommandType.StoredProcedure,
                cancellationToken: cancellationToken));
    }

    private static string? NullIfEmpty(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
