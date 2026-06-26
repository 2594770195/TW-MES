create table MOAllotRequest
(
    MOAllotRequestId     IDType not null
        constraint PK_MOAllotRequest
            primary key,
    RequiredDate         datetime,
    MOAllotRequestStates char(2)
        constraint DF_MOAllotRequest_MOAllotRequestStates default 10,
    CreateUserId         IDType,
    CreateDate           datetime
        constraint DF_MOAllotRequest_CreateDate default getdate(),
    ProductAllotId       nvarchar(256),
    RequestType          char(32)
)
go

