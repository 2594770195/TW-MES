create table Vendor_QCRuleShift
(
    Vendor_QCRuleShiftId char(12) not null
        constraint PK_Vendor_QCRuleShift
            primary key,
    RuleShiftType        char,
    VendorId             char(12),
    Vendor_ProductId     char(12),
    RuleShiftCode        nvarchar(50),
    RuleShiftName        nvarchar(100),
    Times                int
        constraint DF_Vendor_QCRuleShift_Times default 0,
    IsActivity           bit
        constraint DF_Vendor_QCRuleShift_IsActivity default 1,
    ValidRangeDay        int
        constraint DF_Vendor_QCRuleShift_ValidRangeDay default 0,
    CreateDate           datetime
        constraint DF_Vendor_QCRuleShift_CreateDate default getdate(),
    CreateUserId         char(12)
)
go

