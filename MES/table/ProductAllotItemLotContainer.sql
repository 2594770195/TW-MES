create table ProductAllotItemLotContainer
(
    -- 主键：调拨明细批号-容器关联表
    ProductAllotItemLotContainerId char(12)
        -- 主键默认值：6位秒级时间戳(1970-01-01起秒数右6位) + 6位随机hex，共12位
        constraint DF_ProductAllotItemLotContainer_ProductAllotItemLotContainerId default (RIGHT(CONVERT(varchar(20), DATEDIFF_BIG(SECOND, '1970-01-01', GETDATE())), 6) + SUBSTRING(CONVERT(char(36), NEWID(), 0), 1, 6)) not null
        constraint PK_ProductAllotItemLotContainer
            primary key,
    -- 关联调拨明细批号
    ProductAllotItemLotId char(12),
    -- 容器码
    ContainerCode nvarchar(50),
    -- 重量/实际数量
    num float
        constraint DF_ProductAllotItemLotContainer_num default 0,
    -- 货位码(移动目标货位)
    CodeStatus nvarchar(50),
    -- 创建人
    CreateUserId char(12),
    -- 创建时间
    CreateDate datetime
        constraint DF_ProductAllotItemLotContainer_CreateDate default getdate()
)
go