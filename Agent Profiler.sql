--Built stored procedure in MS SQL that parses into Teradata Data Warehouse
--Returns list of authorised agents and directors for a particular identifier
--Source Enterprise Client Addresses and Business Directory of Associates and Relationships
--Takes key value pair user input from URL
--Datasets and columns sanitised

Declare @LinkedServer 	VARCHAR(50)
,		@ID 			VARCHAR(MAX)
,		@SQL			VARCHAR(MAX)
,		@Params			VARCHAR(MAX)

Set @CentralServer = dbo.fnDefault_GetValue('CentralServer')
Set @Params = @strOthersParameters

------Obtain key value pair parameters from URL - example http://XYZ.com?colour=blue&name=bob
If Left(@Params, 1) = '|'
Begin
	Declare @strExecute VARCHAR(MAX)

	CREATE TABLE #params
	(
		[ParamName]		VARCHAR(50)
	,	[ParamValue]	VARCHAR(500)
	)

	Set @strExecute = Replace(Replace(@Params, '=', ''', '''), '|', '''; Insert #params SELECT ''') + ''''
	Set @strExecute = Right(@strExecute, Len(@strExecute) - 2)

	Begin Try
		Exec(@strExecute)
	End Try
	Begin Catch
		Select '<h4>Error with ' + @Params + ' (@Params) - exiting now<h4>'
		Goto Exitproc
	End Catch
	
	Select @ID = Cast(Max(CASE WHEN [ParamName] = 'ID' THEN [ParamValue] END) AS VARCHAR(MAX)
	FROM #params
End
Else
Begin
	SELECT -1 AS Value, 'No parameters were passed' AS Comment
	Goto ExitProc
END

------------------------------------------------------------------------------------------------------
CREATE TABLE #tempTable (
	DATASOURCE 				VARCHAR(40)
	,[Full Name] 			VARCHAR(MAX)
	,[Effective Start Date] VARCHAR(15)
	,[Position Held] 		VARCHAR(MAX)
)

--Teradata SQL - Parse and execute in Teradata
Set @SQL = 'SELECT * FROM OPENQUERY(' + @CentralServer + ',''

--Enterprise Client Address Data
SELECT
	CAST(''''ENT CLIENT ADDRESS'''' AS VARCHAR(100)) AS DATASOURCE,
	,CLNT_ADDR.Authorised_Agent AS Full_Name
	,CAST(CAST(CLNT_ADDR.Authorised_Agent_Start_Date AS FORMAT ''''dd/mm/yyyy'''') AS VARCHAR(15)
	,CLNT_ADDR.Position_Held AS Position_Held

FROM ENTDBO.CLIENT_ADDRESSES CLNT_ADDR
WHERE
	CLNT_ADDR.Authorised_Agent_Record_End_Date > CURRENT_DATE --Bitemporal model
	AND CLNT_ADDR.Authorised_Agent_Effective_End_Date > CURRENT_DATE --Bitemporal model
	AND CLNT_ADDR.Authorised_Agent_Position_Held IS NOT NULL

UNION

--Business Directory Data	
SELECT
	CAST(''''BUSINESS DIRECTORY'''' AS VARCHAR(100)) AS DATASOURCE
	,BUS_ASC_DETAILS.Associate_Name AS Full_Name
	,CAST(CAST(BUS_DIR.Associate_Relationship_Start_Date AS FORMAT ''''dd/mm/yyyy'''') AS VARCHAR(15)
	,BUS_DIR.Position_Held AS Position_Held
FROM EntDBO.Business_Directory AS BUS_DIR
INNER JOIN (
	SELECT
		BUS_ASC.Primary_ID
		,BUS_ASC.Associate_ID
		,BUS_ASC.Associate_Name
	FROM EntDBO.Business_Associates BUS_ASC
	--Need to match with separate matching database between person ID and client ID
	LEFT JOIN EntDBO.ID_Business_ID_Match MATCH_DB
	ON BUS_ASC.Person_ID = MATCH_DB.ID
) BUS_ASC_DETAILS
ON BUS_DIR.ID = BUS_ASC_DETAILS.Primary_ID
WHERE
	BUS_DIR.Associate_Record_End_Date > CURRENT_DATE --Bitemporal model
	AND BUS_DIR.Associate_Effective_End_Date > CURRENT_DATE --Bitemporal model
	AND BUS_DIR.Position_Held IS NOT NULL

;'')'

--------------------Execute and finalise in MS SQL Server
Exec('INSERT INTO #tempTable ' + @SQL)
SELECT * FROM #tempTable;
DROP TABLE #tempTable;
DROP TABLE #params;
Exitproc: