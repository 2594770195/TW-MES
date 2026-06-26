create table SysUser
(
    UserId                    char(12)
        constraint DF_SysUser_UserId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_SysUser
            primary key,
    UserName                  nvarchar(100)
        constraint IX_SysUser
            unique,
    UserDescription           nvarchar(200),
    UserSex                   char
        constraint DF_SysUser_UserSex default 'M',
    UserPassword              varbinary(500),
    Division                  nvarchar(100),
    DivisionId                char(12),
    duties                    nvarchar(30),
    ChangePasswordDate        datetime
        constraint DF_SysUser_ChangePasswordDate default getdate(),
    IsPasswordLongLive        bit
        constraint DF_SysUser_IsPasswordLongLive default 0,
    IsChangePasswordWhenLogin bit
        constraint DF_SysUser_IsChangePasswordWhenLogin default 1,
    IsActivity                bit
        constraint DF_SysUser_IsActive default 1,
    MailAddress               nvarchar(100),
    Phone                     nvarchar(100),
    Protected                 bit
        constraint DF_SysUser_Protected default 0,
    PasswordErrorDate         datetime,
    IsInquireOnlineUser       bit,
    IsRunSCADADesigner        bit,
    FactoryId                 char(12),
    SiteId                    char(12),
    ProductId                 char(12),
    CheckStartDate            datetime,
    CheckEndDate              datetime,
    NoCheckEndDate            bit
        constraint DF__SysUser__NoCheck__607ED58B default 0,
    ShiftId                   char(12),
    GroupsId                  char(12),
    IsOnline                  bit
        constraint DF_SysUser_IsOnline default 0,
    FtpPhoto                  char(12),
    LatestActiveResource      nvarchar(30),
    LatestActivePlugin        nvarchar(30),
    LatestActiveDate          datetime,
    WorkshopId                char(12),
    UserStatus                nvarchar(10)
        constraint DF_SysUser_userstatus default N'在职'                                       not null,
    AutoRunPluginCommand      nvarchar(50),
    IsAccount                 bit
        constraint DF_SysUser_IsAccount default 1,
    IsVendorUser              bit
        constraint DF_SysUser_IsVendorUser default 0,
    IsCustomerUser            bit
        constraint DF_SysUser_IsCustomerUser default 0,
    IsOMFUser                 bit
        constraint DF_SysUser_IsOMFUser default 0,
    IsAdmin                   bit
        constraint DF_SysUser_IsAdmin default 0,
    EmployeeNo                nvarchar(50),
    WorkcenterId              char(12),
    ModifyDate                datetime
        constraint DF_SysUser_ModifyDate default getdate(),
    CreateUserId              char(12),
    CreateDate                datetime
        constraint DF_SysUser_UserRegDate default getdate(),
    LogonLimitedPC            nvarchar(500),
    IsOnlyOneLogin            bit
        constraint DF__SysUser__IsOnlyO__2208DADD default 0,
    WebScadaUserLevel         int,
    WebScadaUserGroupLevel    int,
    UserOldPassword           varbinary(500),
    IsOnlyOneLoginOrDroid     bit default 0,
    IsCallAI                  bit default 0
)
go

