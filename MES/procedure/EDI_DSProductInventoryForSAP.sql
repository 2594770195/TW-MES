SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<HK0269>
-- Create date: <2021.09.13>
-- Description:	<物料批次库存信息接口>
-- Rev: 1.00
-- =============================================
CREATE PROC [dbo].[EDI_DSProductInventoryForSAP]
    @I_ReturnMessage NVARCHAR(MAX) = '' OUTPUT, --返回的信息,支持多语言
    @ItemId CHAR(12) = '',
    @ItemName NVARCHAR(50) = '',                --项目名称
    @IsReturn BIT = 0,                          --上传
    @ET_OUT XML = NULL,
    @ET_MSG XML = NULL,
@Uploadingid  NVARCHAR(50)=''
AS
BEGIN

    -- SET NOCOUNT ON added to prevent extra result sets from
    -- interfering with SELECT statements.
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    SET XACT_ABORT ON;

	IF @IsReturn = 0 --2.
    BEGIN

	DECLARE @OldProductName NVARCHAR(30)=''
	DECLARE @NewProductName NVARCHAR(30)=''

	SELECT @OldProductName=ISNULL(ip.ParameterValue,'') FROM dbo.InputParameter AS ip WHERE ip.InterfaceItemId = @ItemId AND ip.ParameterName='IV_MATNR';

	SELECT TOP 1 @NewProductName=ISNULL(pf.TProductName,'')  FROM dbo.Product AS pf WHERE pf.TProductName>@OldProductName ORDER BY pf.TProductName
	 
	IF ISNULL(@NewProductName,'')=''
	BEGIN 
		SELECT TOP 1 @NewProductName=ISNULL(pf.TProductName,'')  FROM dbo.Product AS pf  ORDER BY pf.TProductName
	END 

	UPDATE dbo.InputParameter SET InputParameter.ParameterValue=@NewProductName WHERE InterfaceItemId = @ItemId AND ParameterName='IV_MATNR';

    RETURN 0;

   
    END;
    ELSE
    BEGIN

    DECLARE @idoc INT;
    DECLARE @xml XML;

    DECLARE @FactoryName NVARCHAR(50);
    DECLARE @ProductName NVARCHAR(50);
    DECLARE @WorkcenterName NVARCHAR(50);
    DECLARE @LotSN NVARCHAR(50);
    DECLARE @ProductInventoryNum DECIMAL(18,4);
    DECLARE @UOMName NVARCHAR(50);
	DECLARE @CheckNum DECIMAL(18,4);
	DECLARE @Note NVARCHAR(50);
	DECLARE @StorageDate NVARCHAR(50);
	DECLARE @LockQty DECIMAL(18,4)
	DECLARE @SOName NVARCHAR(50);
	DECLARE @ItemSequence NVARCHAR(50);


;


    DECLARE @ERPDate DATETIME;
    DECLARE @ProductInventoryId CHAR(12);
    DECLARE @FactoryId CHAR(12);
    DECLARE @ProductId CHAR(12);
    DECLARE @WorkcenterId CHAR(12);
    DECLARE @UOMId CHAR(12);
    DECLARE @SiteId CHAR(12);
    DECLARE @rows INT;
    DECLARE @Count INT;

    SET @Count = 0;
    SET @ProductInventoryId = '';
    SET @SiteId = '';
    SET @idoc = 0;
    SET @I_ReturnMessage = 'ServerMessage:xxxxxxxxxxxxx ';

    BEGIN TRY

        ----定义临时表
        DECLARE @TempTable TABLE
        (
            Id INT IDENTITY(1, 1),
            FactoryName NVARCHAR(50),
            ProductName NVARCHAR(50),
            WorkcenterName NVARCHAR(50),
            LotSN NVARCHAR(50),
            ProductInventoryNum DECIMAL(18,4),
            UOMName NVARCHAR(50),
			CheckNum DECIMAL(18,4),
			Note NVARCHAR(50),
	        StorageDate NVARCHAR(50),
	        LockQty DECIMAL(18,4) ,
			SOName NVARCHAR(50),
	        ItemSequence NVARCHAR(50)
        );
		UPDATE InterfaceItem
        SET LastDate = GETDATE()
        WHERE InterfaceItemId = @ItemId;

        INSERT dbo.EDILog
        (
            LogStr
        )
        VALUES
        (@ItemName + ' ET_OUT=' + CONVERT(NVARCHAR(MAX), @ET_OUT));

        INSERT dbo.EDILog
        (
            LogStr
        )
        VALUES
        (@ItemName + ' ET_MSG=' + CONVERT(NVARCHAR(MAX), @ET_MSG));

        IF @ET_OUT IS NOT NULL
        BEGIN
            SET @xml = @ET_OUT;
            --将XML转换成临时表
            EXEC sp_xml_preparedocument @idoc OUTPUT, @xml;
            INSERT INTO @TempTable
            SELECT *
            FROM
                OPENXML(@idoc, 'DBSET/RECORD', 2)
                --与XML即Excel的列名一致
                WITH
                (
                    FactoryName NVARCHAR(50),
                    ProductName NVARCHAR(50),
                    WorkcenterName NVARCHAR(50),
                    LotSN NVARCHAR(50),
                    ProductInventoryNum DECIMAL(18,4),
                    UOMName NVARCHAR(50),
					CheckNum DECIMAL(18,4),
					Note NVARCHAR(50),
					StorageDate NVARCHAR(50),
					LockQty DECIMAL(18,4),
			        SOName NVARCHAR(50),
	                ItemSequence NVARCHAR(50)
                );


            --销毁 XML
            EXEC sp_xml_removedocument @idoc;

			IF ( ( SELECT COUNT(*) FROM (
			SELECT DISTINCT   FactoryName,ISNULL(dbo.RemovePrefixZero(ProductName),'') AS ProductName,WorkcenterName    
                FROM @TempTable ) t )>2)
            BEGIN 

				UPDATE dbo.ProductInventory SET DeleteFlag='1';
			END 
			ELSE 
			BEGIN
  
			    UPDATE dbo.ProductInventory SET DeleteFlag='1' 
				WHERE FactoryId=(SELECT DISTINCT FactoryId FROM @TempTable AS tt LEFT JOIN dbo.Factory f ON f.FactoryName = tt.FactoryName WHERE ISNULL(tt.LotSN, '') <> '') 
				AND WorkcenterId=(SELECT DISTINCT WorkcenterId FROM @TempTable AS tt LEFT JOIN dbo.Workcenter w ON w.WorkcenterName = tt.WorkcenterName WHERE ISNULL(tt.LotSN, '') <> ''
				                  AND FactoryId=(SELECT DISTINCT FactoryId FROM @TempTable AS tt LEFT JOIN dbo.Factory f ON f.FactoryName = tt.FactoryName WHERE ISNULL(tt.LotSN, '') <> '') ) 
				AND ProductId =(SELECT DISTINCT ProductId FROM @TempTable AS tt LEFT JOIN dbo.ProductRoot pr ON pr.ProductName = ISNULL(dbo.RemovePrefixZero(tt.ProductName),'')
				                                                      LEFT JOIN dbo.Product p ON p.ProductRootId = pr.ProductRootId WHERE ISNULL(tt.LotSN, '') <> '');
            END 

            DECLARE @MaxCnt INT;
            DECLARE @MinCnt INT;
            SELECT @MaxCnt = COUNT(1),
                   @MinCnt = MIN(Id)
            FROM @TempTable;
            SET @Count = @MinCnt;
            WHILE @Count <= @MaxCnt AND 0 < @MaxCnt
            BEGIN

                SELECT @FactoryName = FactoryName,
                       @ProductName = ISNULL(dbo.RemovePrefixZero(ProductName),''),
                       @WorkcenterName = WorkcenterName,
                       @LotSN = LotSN,
                       @ProductInventoryNum = ProductInventoryNum,
                       @UOMName = UOMName,
					   @CheckNum=CheckNum,
					   @Note=Note,
	                   @StorageDate=StorageDate,
	                   @LockQty=LockQty ,
			           @SOName= SOName,
	                   @ItemSequence= ItemSequence
                FROM @TempTable
                WHERE Id = @Count;

				
                --检查是批号否为空
                IF ISNULL(@LotSN, '') = ''
                BEGIN
				   --更新输入参数值
                   SET @Count = @Count + 1;
                   CONTINUE;
                END;

                --检查是否为空
                IF ISNULL(@ProductName, '') = ''
                BEGIN
                    SET @I_ReturnMessage = 'ServerMessage:产品名称不能为空!';
                END;

                SELECT @FactoryId = FactoryId
                FROM Factory
                WHERE Factory.FactoryName = @FactoryName;
                SELECT @ProductId = ProductId
                FROM Product
                    INNER JOIN ProductRoot
                        ON ProductRoot.ProductRootId = Product.ProductRootId
                WHERE ProductName = @ProductName;

                SELECT @WorkcenterId = WorkcenterId
                FROM Workcenter
                WHERE WorkcenterName = @WorkcenterName AND FactoryId=@FactoryId;
                SELECT @UOMId = UOMId
                FROM UOM
                WHERE UOMName = @UOMName;

                IF NOT EXISTS
                (
                    SELECT ProductInventoryId
                    FROM dbo.ProductInventory
                    WHERE LotSN = @LotSN AND ProductId=@ProductId AND WorkcenterId=@WorkcenterId AND FactoryId=@FactoryId
                )
                BEGIN
                    --申请主键
                    EXEC SysGetObjectPKId '', 'ProductInventory', @ProductInventoryId OUTPUT;
                    INSERT INTO [dbo].ProductInventory
                    (
                        ProductInventoryId,
                        FactoryId,
                        ProductId,
                        WorkcenterId,
                        LotSN,
                        ProductInventoryNum,
                        UOMId,
						DeleteFlag,
						CheckNum,
						Note,
	                    StorageDate,
	                    LockQty ,SOName,ItemSequence
                    )
                    VALUES
                    (@ProductInventoryId, @FactoryId, @ProductId, @WorkcenterId, @LotSN, @ProductInventoryNum, @UOMId,'0',@CheckNum,
					@Note,@StorageDate,@LockQty,@SOName,@ItemSequence);
                END;
                ELSE
                BEGIN
                    SELECT @ProductInventoryId = ProductInventoryId
                    FROM ProductInventory
                    WHERE LotSN = @LotSN AND ProductId=@ProductId AND WorkcenterId=@WorkcenterId AND FactoryId=@FactoryId;

                    IF ISNULL(@ProductInventoryId, '') <> ''
                    BEGIN
                        UPDATE ProductInventory
                        SET FactoryId = @FactoryId,
                            ProductId = @ProductId,
                            WorkcenterId = @WorkcenterId,
                            LotSN = @LotSN,
                            ProductInventoryNum = @ProductInventoryNum,
                            UOMId = @UOMId,
							DeleteFlag='0',
							CheckNum=@CheckNum,
							Note=@Note,
	                        StorageDate=@StorageDate,
	                        LockQty=@LockQty ,
							SOName=@SOName,
							ItemSequence=@ItemSequence
                        WHERE ProductInventoryId = @ProductInventoryId;
                    END;
                END;

                --更新输入参数值
                SET @Count = @Count + 1;
            END;
			SET @I_ReturnMessage
				= 'ServerMessage:成功同步 ' + CAST(ISNULL(@Count, 0) AS VARCHAR) + ' 行数据...ET_MSG='
				  + ISNULL(CONVERT(NVARCHAR(MAX), @ET_MSG),'') ;
        END;
		ELSE
		BEGIN
			SET @I_ReturnMessage
				= 'ServerMessage: MES ' + @ItemName + ' @ET_OUT=[' + CAST(ISNULL(@ET_OUT,'') AS NVARCHAR(500))+  '],参数@ET_MSG IS NULL' 

		END



    END TRY
    BEGIN CATCH
        SET @I_ReturnMessage
            = 'ServerMessage: MES ' + @ItemName + ' @ET_OUT=[' + CAST(ISNULL(@ET_OUT,'') AS NVARCHAR(MAX))+ ']'+ ' @ET_MSG=[' + CAST(ISNULL(@ET_MSG,'') AS NVARCHAR(MAX))+ '],'+
			' 导入时发生错误：' + CHAR(13) + CHAR(10) + '['
              + LTRIM(RTRIM(CONVERT(CHAR(100), ERROR_NUMBER()))) + ']' + ERROR_MESSAGE()+'  '+ERROR_LINE();

        IF ISNULL(@I_ReturnMessage, '') <> ''
            INSERT INTO InterfaceLog
            (
                LogContent
            )
            VALUES
            (@I_ReturnMessage);

        RETURN -1;

    END CATCH;

	

    RETURN 0;

	END 
END;
GO
