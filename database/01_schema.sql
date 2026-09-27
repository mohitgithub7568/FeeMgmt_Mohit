-- =====================================================
-- Fee Management System - Tables
-- =====================================================

-- Students: one row per student with their fee details
CREATE TABLE dbo.Students (
    StudentID          INT            NOT NULL PRIMARY KEY,
    Name               NVARCHAR(100)  NOT NULL,
    Email              NVARCHAR(255)  NOT NULL,          -- needed to send reminders
    Course             NVARCHAR(100)  NOT NULL,
    TotalFee           DECIMAL(12,2)  NOT NULL,          -- DECIMAL, not FLOAT: money must be exact
    PaidAmount         DECIMAL(12,2)  NOT NULL DEFAULT (0),
    DueDate            DATE           NOT NULL,
    LastReminderSentAt DATETIME2      NULL,              -- so we don't email the same student every day
    IsTestData         BIT            NOT NULL DEFAULT (0), -- 1 = fake load-test row, never emailed
    CONSTRAINT CK_Students_TotalFee CHECK (TotalFee >= 0),
    CONSTRAINT CK_Students_Paid     CHECK (PaidAmount >= 0 AND PaidAmount <= TotalFee)
);

-- Administrators: staff who manage fees
CREATE TABLE dbo.Administrators (
    AdminID  INT            NOT NULL PRIMARY KEY,
    Name     NVARCHAR(100)  NOT NULL,
    Role     NVARCHAR(50)   NOT NULL,
    CONSTRAINT CK_Admin_Role CHECK (Role IN ('SuperAdmin', 'FeeManager', 'Viewer'))
);

-- Index: makes "find overdue students" fast even with thousands of rows
CREATE NONCLUSTERED INDEX IX_Students_DueDate
    ON dbo.Students (DueDate)
    INCLUDE (TotalFee, PaidAmount, Name, Email, LastReminderSentAt, IsTestData);
