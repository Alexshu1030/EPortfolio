USE [ResponseDriver]
GO

/****** Object:  StoredProcedure [dbo].[UpdateUserInactive]    Script Date: 2021-10-19 2:15:12 PM ******/

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/******************************************************************
** Name: UpdateUserInactive
** Desc: Update user flag Inactive to 0 if user inactive and if
**   SpecialUser do UpdateUserProfile.
**   If an user does not log into the system in last 120 days the user
**   will be marked as inactive, the leads will not be distributed to
**   these users
**
**      This is for the job named: RD Update Inactive Users Profiles
**
** Author: JTanuan
** Date: 2021-10-19
*******************************************************************
** Change History
*******************************************************************
** Date:      Author:   Description:
** --------   --------  -----------------------------------------
** 2021-10-19 JTanuan   Initial implementation
*******************************************************************/

CREATE PROCEDURE [dbo].[UpdateUserInactive]
AS
BEGIN
  SET NOCOUNT ON;
  -- Variables
  DECLARE
  @count int = 0,
  @processAmount int,
  @CompanyID int,
  @UserID int,
  @BaseCommandID int = 9, -- UpdateUserProfile
  @GlobalAttID int = 31 -- SpecialUserID

  DECLARE @InactiveUsers TABLE (MembershipUserID uniqueidentifier, ID int, CompanyID int)

  -- Get all users with lastLoginDate > 120 days
  INSERT INTO @InactiveUsers
  SELECT
  logins.membershipUserID AS MembershipUserID,
  logins.ID AS ID,
  logins.CompanyID AS CompanyID
  FROM [dbo].[Logins] AS logins
  INNER JOIN [dbo].[Membership] AS Membership ON logins.membershipUserID = Membership.UserId
  WHERE Membership.Inactive = 1
  AND DATEDIFF(day, Membership.LastLoginDate, GETUTCDATE()) > 120

  -- Update Inactive to 0
  UPDATE [dbo].[Membership]
  SET Inactive = 0
  WHERE UserID IN
  (
    SELECT iu.MembershipUserID
    FROM @InactiveUsers iu
  )

  -- Get total amount of users with SpecialUserID
  SET @processAmount =
  (
    SELECT COUNT(iu.ID)
    FROM @InactiveUsers iu
    INNER JOIN [ResponseDriver].[dbo].[Global_Attribute] as Global_Attribute ON Global_Attribute.User_ID = iu.ID
    WHERE Global_Attribute.MetadataField_ID = @GlobalAttID
  )

  WHILE @count < @processAmount
  BEGIN
    -- Check if SpecialUserID exists for each user
    SELECT TOP 1
    @CompanyID = iu.CompanyID,
    @UserID = iu.ID
    FROM @InactiveUsers iu
    INNER JOIN [ResponseDriver].[dbo].[Global_Attribute] as Global_Attribute ON Global_Attribute.User_ID = iu.ID
    WHERE Global_Attribute.MetadataField_ID = @GlobalAttID

    -- Do UpdateUserProfile for users with a SpecialUserID
    IF @UserID IS NOT NULL AND @CompanyID IS NOT NULL
    BEGIN
          -- Insert to ComandTaskQueue to update the user profile.
      EXEC CommandTaskQueue_AddByBaseCommandID NULL, @CompanyID, NULL, @UserID, @BaseCommandID, NULL, @UserID
      DELETE FROM @InactiveUsers WHERE ID = @UserID
    END

    SET @count = @count + 1

  END
END
;