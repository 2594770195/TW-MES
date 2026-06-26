create table UserCertificate
(
    UserCertificateId  char(12)
        constraint DF_UserCertificate_UserCertificateId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_UserCertificate
            primary key,
    UserId             char(12),
    CertificateName    nvarchar(50),
    IssuingInstitution nvarchar(50),
    IssuingDate        datetime,
    ExpirationDate     datetime,
    AuditCycle         int,
    CertificateStatus  nvarchar(50),
    Remarks            nvarchar(50),
    FtpCertificate     char(12),
    CreateBy           char(12),
    CreateDate         datetime
)
go

