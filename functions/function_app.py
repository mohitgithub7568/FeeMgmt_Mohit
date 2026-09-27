import json
import logging
import os
import time
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation

import azure.functions as func
import pyodbc

# Callers need a function key. Only API Management has it (keys are not checked by `func start`).
app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

# Azure runs in UTC, so "today" is always calculated in IST.
IST = timezone(timedelta(hours=5, minutes=30))

STUDENT_COLUMNS = "StudentID, Name, Course, TotalFee, PaidAmount, DueDate"

# Same rule as calculate_fee_status(), in SQL, so search can filter by status. ? = today (IST).
STATUS_SQL = """
    CASE
        WHEN PaidAmount >= TotalFee THEN 'Paid'
        WHEN DueDate < ? THEN 'Overdue'
        WHEN PaidAmount > 0 THEN 'Partially Paid'
        ELSE 'Pending'
    END
"""
VALID_STATUSES = {"Paid", "Partially Paid", "Overdue", "Pending"}
MAX_PAGE_SIZE = 100
CONNECT_ATTEMPTS = 4


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def get_connection() -> pyodbc.Connection:
    """Connect to Azure SQL, retrying while a paused serverless database wakes up."""
    for attempt in range(1, CONNECT_ATTEMPTS + 1):
        try:
            return pyodbc.connect(os.environ["SQL_CONNECTION_STRING"])
        except pyodbc.Error as error:
            if attempt == CONNECT_ATTEMPTS:
                raise
            wait = 5 * attempt
            logging.warning("SQL connect attempt %s failed (%s); retrying in %ss", attempt, error, wait)
            time.sleep(wait)


def today_ist() -> date:
    return datetime.now(IST).date()


def json_response(body: dict, status_code: int = 200) -> func.HttpResponse:
    return func.HttpResponse(json.dumps(body), status_code=status_code, mimetype="application/json")


def calculate_fee_status(total_fee: Decimal, paid_amount: Decimal, due_date: date, today: date) -> str:
    """Business rule for fee status. Order of checks matters."""
    if paid_amount >= total_fee:
        return "Paid"
    if due_date < today:
        return "Overdue"
    if paid_amount > 0:
        return "Partially Paid"
    return "Pending"


def to_fee_dict(row, today: date) -> dict:
    """Turn a Students row into the JSON shape used by every endpoint."""
    status = calculate_fee_status(row.TotalFee, row.PaidAmount, row.DueDate, today)
    return {
        "studentId": row.StudentID,
        "name": row.Name,
        "course": row.Course,
        "totalFee": float(row.TotalFee),
        "paidAmount": float(row.PaidAmount),
        "balance": float(row.TotalFee - row.PaidAmount),
        "dueDate": row.DueDate.isoformat(),
        "daysOverdue": (today - row.DueDate).days if status == "Overdue" else 0,
        "status": status,
    }


def parse_money(value) -> Decimal:
    """Turn a JSON value into an exact Decimal; reject text, true/false, NaN, Infinity."""
    amount = Decimal(str(value))
    if not amount.is_finite():
        raise ValueError("not a finite number")
    return amount


# ---------------------------------------------------------------------------
# Student API
# ---------------------------------------------------------------------------

@app.route(route="students/{studentId}/status", methods=["GET"])
def get_fee_status(req: func.HttpRequest) -> func.HttpResponse:
    student_id = req.route_params.get("studentId")

    # The ID arrives from the URL as text, so make sure it is a number
    if not student_id.isdigit():
        return json_response({"error": "studentId must be a number"}, 400)

    conn = get_connection()
    try:
        row = conn.cursor().execute(
            f"SELECT {STUDENT_COLUMNS} FROM dbo.Students WHERE StudentID = ?", int(student_id)
        ).fetchone()
    finally:
        conn.close()

    if row is None:
        return json_response({"error": f"Student {student_id} not found"}, 404)

    return json_response(to_fee_dict(row, today_ist()))


# ---------------------------------------------------------------------------
# Admin API (protected in APIM by Entra ID roles)
# Routes start with "manage/" because Azure Functions reserves routes starting with "admin".
# ---------------------------------------------------------------------------

@app.route(route="manage/students", methods=["GET"])
def admin_query_students(req: func.HttpRequest) -> func.HttpResponse:
    status = req.params.get("status")
    course = req.params.get("course")
    page_text = req.params.get("page", "1")
    size_text = req.params.get("pageSize", "20")

    if not page_text.isdigit() or not size_text.isdigit():
        return json_response({"error": "page and pageSize must be positive numbers"}, 400)
    if status and status not in VALID_STATUSES:
        return json_response({"error": f"status must be one of {sorted(VALID_STATUSES)}"}, 400)

    page = max(int(page_text), 1)
    page_size = min(max(int(size_text), 1), MAX_PAGE_SIZE)
    today = today_ist()

    # User values are only passed as ? parameters
    conditions, params = [], []
    if status:
        conditions.append(f"{STATUS_SQL} = ?")
        params += [today, status]
    if course:
        conditions.append("Course = ?")
        params.append(course)
    where_sql = ("WHERE " + " AND ".join(conditions)) if conditions else ""

    conn = get_connection()
    try:
        cursor = conn.cursor()
        total = cursor.execute(f"SELECT COUNT(*) FROM dbo.Students {where_sql}", *params).fetchval()
        rows = cursor.execute(
            f"SELECT {STUDENT_COLUMNS} FROM dbo.Students {where_sql} "
            "ORDER BY StudentID OFFSET ? ROWS FETCH NEXT ? ROWS ONLY",
            *params, (page - 1) * page_size, page_size,
        ).fetchall()
    finally:
        conn.close()

    return json_response({
        "page": page,
        "pageSize": page_size,
        "total": total,
        "items": [to_fee_dict(r, today) for r in rows],
    })


@app.route(route="manage/students/{studentId}/fee", methods=["PATCH"])
def admin_update_fee(req: func.HttpRequest) -> func.HttpResponse:
    student_id = req.route_params.get("studentId")
    if not student_id.isdigit():
        return json_response({"error": "studentId must be a number"}, 400)

    # 1. Validate the request body
    try:
        body = req.get_json()
    except ValueError:
        return json_response({"error": "Body must be valid JSON"}, 400)
    if not isinstance(body, dict):
        return json_response({"error": "Body must be a JSON object"}, 400)
    try:
        new_total = parse_money(body["totalFee"]) if "totalFee" in body else None
        new_paid = parse_money(body["paidAmount"]) if "paidAmount" in body else None
        new_due = date.fromisoformat(body["dueDate"]) if "dueDate" in body else None
    except (InvalidOperation, ValueError, TypeError):
        return json_response({"error": "totalFee/paidAmount must be numbers, dueDate must be YYYY-MM-DD"}, 400)
    if new_total is None and new_paid is None and new_due is None:
        return json_response({"error": "Send at least one of totalFee, paidAmount, dueDate"}, 400)

    # Set by API Management from the caller's token
    changed_by = req.headers.get("X-Caller-Id", "unknown")

    conn = get_connection()
    try:
        cursor = conn.cursor()

        # 2. Read the current row and lock it until commit
        old = cursor.execute(
            f"SELECT {STUDENT_COLUMNS} FROM dbo.Students WITH (UPDLOCK) WHERE StudentID = ?",
            int(student_id),
        ).fetchone()
        if old is None:
            return json_response({"error": f"Student {student_id} not found"}, 404)

        # 3. Merge: fields not sent keep their old value
        total = new_total if new_total is not None else old.TotalFee
        paid = new_paid if new_paid is not None else old.PaidAmount
        due = new_due if new_due is not None else old.DueDate
        if total < 0 or paid < 0 or paid > total:
            return json_response({"error": "Must satisfy 0 <= paidAmount <= totalFee"}, 400)

        # 4. Update the student and write the audit row
        cursor.execute(
            "UPDATE dbo.Students SET TotalFee = ?, PaidAmount = ?, DueDate = ? WHERE StudentID = ?",
            total, paid, due, int(student_id),
        )
        cursor.execute(
            "INSERT INTO dbo.FeeAuditLog (StudentID, ChangedBy, OldTotalFee, NewTotalFee, "
            "OldPaidAmount, NewPaidAmount, OldDueDate, NewDueDate) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            int(student_id), changed_by, old.TotalFee, total, old.PaidAmount, paid, old.DueDate, due,
        )

        # 5. Commit both changes together (on any error nothing is saved)
        conn.commit()

        updated = cursor.execute(
            f"SELECT {STUDENT_COLUMNS} FROM dbo.Students WHERE StudentID = ?", int(student_id)
        ).fetchone()
    finally:
        conn.close()

    logging.info("Fee updated: student=%s by=%s paid %s -> %s", student_id, changed_by, old.PaidAmount, paid)
    return json_response(to_fee_dict(updated, today_ist()))
