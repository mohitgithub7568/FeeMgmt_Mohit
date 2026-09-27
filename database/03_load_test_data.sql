-- =====================================================
-- Load test data: 5,000 fake students (IDs 100001-105000)
-- IsTestData = 1 and .invalid emails, so these rows are never emailed.
-- =====================================================

SET NOCOUNT ON;

DECLARE @today DATE = CAST(GETDATE() AS DATE);
DECLARE @i INT = 1;
DECLARE @total DECIMAL(12,2);

BEGIN TRANSACTION;

WHILE @i <= 5000
BEGIN
    SET @total = CASE @i % 4 WHEN 0 THEN 60000 WHEN 1 THEN 90000 WHEN 2 THEN 150000 ELSE 200000 END;

    INSERT INTO dbo.Students (StudentID, Name, Email, Course, TotalFee, PaidAmount, DueDate, IsTestData)
    VALUES (
        100000 + @i,
        CONCAT('Load Test Student ', @i),
        CONCAT('loadtest', @i, '@example.invalid'),
        CASE @i % 6 WHEN 0 THEN 'B.Tech CSE' WHEN 1 THEN 'MBA' WHEN 2 THEN 'BBA'
                    WHEN 3 THEN 'M.Tech AI' WHEN 4 THEN 'B.Com' ELSE 'BCA' END,
        @total,
        CASE @i % 4 WHEN 0 THEN @total WHEN 1 THEN @total / 2 WHEN 2 THEN @total / 4 ELSE 0 END,  -- full, half, quarter or nothing paid
        DATEADD(DAY, (@i % 120) - 60, @today),                                                   -- due between 60 days ago and 60 days ahead
        1
    );

    SET @i = @i + 1;
END;

COMMIT;

PRINT '5000 test students added';
