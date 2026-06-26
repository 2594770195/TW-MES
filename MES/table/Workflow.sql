create table Workflow
(
    WorkflowId          char(12)
        constraint DF_Workflow_WorkflowId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Workflow
            primary key,
    WorkflowRootId      char(12),
    WorkflowRevision    nvarchar(20)
        constraint DF_Workflow_WorkflowRevision default 1.0,
    WorkflowDescription nvarchar(200),
    IsActivity          bit
        constraint DF_Workflow_IsActivity default 1,
    IsDefaultWorkflow   bit
        constraint DF_Workflow_IsDefaultWorkflow default 1,
    IsMetadataFlow      bit,
    WorkflowType        nvarchar(50),
    CreateUserId        char(12),
    CreateDate          datetime
        constraint DF_Workflow_CreateDate default getdate(),
    ApplicableTypeId    nvarchar(50)
)
go

