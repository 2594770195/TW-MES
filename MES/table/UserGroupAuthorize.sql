create table UserGroupAuthorize
(
    UserGroupAuthorizeId char(12) not null
        constraint PK_SiteUserGroup
            primary key,
    UserGroupId          char(12),
    UserId               char(12)
)
go

