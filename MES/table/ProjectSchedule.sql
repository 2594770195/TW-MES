create table ProjectSchedule
(
    ProjectScheduleID char(12) not null
        constraint PK_ProjectSchedule
            primary key,
    TaskNO            int,
    Task              nchar(100),
    PIC               nchar(50),
    Planstart         datetime,
    PlanEnd           datetime,
    startInfact       datetime,
    endInfact         datetime,
    status            nchar(10),
    Remark            nchar(100),
    IsKeyTask         bit,
    ProjectID         char(12)
)
go

