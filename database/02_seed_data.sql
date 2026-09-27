-- =====================================================
-- Sample data: 20 students + 3 administrators
-- Run with sqlcmd variables so no real email is stored in git:
--   sqlcmd ... -v EmailUser="yourname" EmailDomain="gmail.com" -i 02_seed_data.sql
-- Every student gets yourname+stuNNNN@domain, which all land in YOUR inbox.
-- Due dates are relative to today, so there are always overdue students.
-- =====================================================

DECLARE @today DATE = CAST(GETDATE() AS DATE);

INSERT INTO dbo.Students (StudentID, Name, Email, Course, TotalFee, PaidAmount, DueDate) VALUES
(1001, 'Aarav Sharma',     '$(EmailUser)+stu1001@$(EmailDomain)', 'B.Tech CSE', 150000, 150000, DATEADD(DAY, -30, @today)), -- Paid
(1002, 'Diya Patel',       '$(EmailUser)+stu1002@$(EmailDomain)', 'B.Tech CSE', 150000,  75000, DATEADD(DAY,  20, @today)), -- Partially Paid
(1003, 'Vivaan Gupta',     '$(EmailUser)+stu1003@$(EmailDomain)', 'B.Tech CSE', 150000,  50000, DATEADD(DAY, -10, @today)), -- Overdue
(1004, 'Ananya Iyer',      '$(EmailUser)+stu1004@$(EmailDomain)', 'MBA',        200000,      0, DATEADD(DAY,  -5, @today)), -- Overdue
(1005, 'Arjun Reddy',      '$(EmailUser)+stu1005@$(EmailDomain)', 'MBA',        200000, 120000, DATEADD(DAY,  15, @today)), -- Partially Paid
(1006, 'Ishita Verma',     '$(EmailUser)+stu1006@$(EmailDomain)', 'MBA',        200000, 200000, DATEADD(DAY, -60, @today)), -- Paid
(1007, 'Kabir Singh',      '$(EmailUser)+stu1007@$(EmailDomain)', 'BBA',         90000,      0, DATEADD(DAY,  30, @today)), -- Pending
(1008, 'Meera Nair',       '$(EmailUser)+stu1008@$(EmailDomain)', 'BBA',         90000,  45000, DATEADD(DAY,  -2, @today)), -- Overdue
(1009, 'Rohan Das',        '$(EmailUser)+stu1009@$(EmailDomain)', 'BBA',         90000,  90000, DATEADD(DAY, -15, @today)), -- Paid
(1010, 'Saanvi Joshi',     '$(EmailUser)+stu1010@$(EmailDomain)', 'M.Tech AI',  180000,  60000, DATEADD(DAY, -20, @today)), -- Overdue
(1011, 'Aditya Kumar',     '$(EmailUser)+stu1011@$(EmailDomain)', 'M.Tech AI',  180000, 180000, DATEADD(DAY,  -1, @today)), -- Paid
(1012, 'Kiara Mehta',      '$(EmailUser)+stu1012@$(EmailDomain)', 'M.Tech AI',  180000,  90000, DATEADD(DAY,  45, @today)), -- Partially Paid
(1013, 'Reyansh Rao',      '$(EmailUser)+stu1013@$(EmailDomain)', 'B.Com',       60000,      0, DATEADD(DAY, -45, @today)), -- Overdue
(1014, 'Aadhya Pillai',    '$(EmailUser)+stu1014@$(EmailDomain)', 'B.Com',       60000,  30000, DATEADD(DAY,  10, @today)), -- Partially Paid
(1015, 'Vihaan Malhotra',  '$(EmailUser)+stu1015@$(EmailDomain)', 'B.Com',       60000,  60000, DATEADD(DAY,  -7, @today)), -- Paid
(1016, 'Myra Kapoor',      '$(EmailUser)+stu1016@$(EmailDomain)', 'BCA',         80000,  20000, DATEADD(DAY,  -3, @today)), -- Overdue
(1017, 'Ayaan Chatterjee', '$(EmailUser)+stu1017@$(EmailDomain)', 'BCA',         80000,  80000, DATEADD(DAY, -90, @today)), -- Paid
(1018, 'Anika Bose',       '$(EmailUser)+stu1018@$(EmailDomain)', 'BCA',         80000,  40000, DATEADD(DAY,  25, @today)), -- Partially Paid
(1019, 'Krishna Menon',    '$(EmailUser)+stu1019@$(EmailDomain)', 'MCA',        120000,      0, DATEADD(DAY,  60, @today)), -- Pending
(1020, 'Pari Saxena',      '$(EmailUser)+stu1020@$(EmailDomain)', 'MCA',        120000, 100000, DATEADD(DAY, -12, @today)); -- Overdue

INSERT INTO dbo.Administrators (AdminID, Name, Role) VALUES
(1, 'Mohit Soni',  'SuperAdmin'),
(2, 'Priya Desai', 'FeeManager'),
(3, 'Rahul Jain',  'Viewer');
