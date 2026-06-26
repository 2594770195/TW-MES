CREATE TABLE PUnpackRecord
(
    UnpackRecordId IDType
        CONSTRAINT DF_PUnpackRecord_UnpackRecordId DEFAULT substring(CONVERT([char](36), newid(), 0), 1, 12) NOT NULL
        CONSTRAINT PK_PUnpackRecord
            PRIMARY KEY,
    EmployeeNo     nvarchar(50) NOT NULL, -- 人员工号
    MOId           IDType       NOT NULL, -- 工单ID（扫LotSN时从Lot反查）
    LotSN          LotSN        NOT NULL, -- 批次条码
    StartTime      datetime     NOT NULL, -- 开始时间
    EndTime        datetime,              -- 结束时间（为空表示未结束）
    CreateUserId   IDType,                -- 创建人
    CreateDate     datetime  DEFAULT getdate(), -- 创建时间
    ModifyDate     datetime DEFAULT getdate()  -- 修改时间
)
GO


