create table ZR_WorkflowConfig
(
    WorkflowConfigId char(12) not null
        constraint ZR_WorkflowConfig_pk
            primary key,
    Evn              nvarchar(255),
    WorkflowId       char(12),
    WorkflowName     nvarchar(255),
    UpdateDate       datetime,
    CreateDate       datetime default getdate()
)
go

