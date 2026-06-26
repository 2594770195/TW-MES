namespace StocktakeImport.Api.Models;

/// <summary>
/// 统一 API 响应格式
/// </summary>
public class ApiResponse<T>
{
    public int Code { get; set; }
    public string Message { get; set; } = string.Empty;
    public T? Data { get; set; }

    public static ApiResponse<T> Ok(T data, string message = "成功") =>
        new() { Code = 0, Message = message, Data = data };

    public static ApiResponse<T> Fail(string message, int code = 1) =>
        new() { Code = code, Message = message };
}

public class ParseExcelResult
{
    public List<StocktakeRow> Rows { get; set; } = [];
    public List<string> Errors { get; set; } = [];
    public int TotalRows { get; set; }
}

public class ExecuteStocktakeRequest
{
    public bool DryRun { get; set; } = true;
    public string CreateUserId { get; set; } = string.Empty;
}

public class ExecuteStocktakeResult
{
    public string RawJson { get; set; } = string.Empty;
    public object? Parsed { get; set; }
}
