-- =====================================================
-- Audit log: one row for every admin change to a student's fee record
-- Who changed what, old value -> new value, and when (UTC).
-- =====================================================

CREATE TABLE dbo.FeeAuditLog (
    AuditID       BIGINT IDENTITY(1,1) PRIMARY KEY,
    StudentID     INT           NOT NULL REFERENCES dbo.Students(StudentID), -- must be a real student
    ChangedBy     NVARCHAR(200) NOT NULL,                              -- admin identity (from the login token)
    OldTotalFee   DECIMAL(12,2) NOT NULL,
    NewTotalFee   DECIMAL(12,2) NOT NULL,
    OldPaidAmount DECIMAL(12,2) NOT NULL,
    NewPaidAmount DECIMAL(12,2) NOT NULL,
    OldDueDate    DATE          NOT NULL,
    NewDueDate    DATE          NOT NULL,
    ChangedAt     DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME())    -- stamped automatically
);
