import os
from datetime import datetime, date, timedelta
import calendar
from typing import Optional, List
from typing import Literal
from decimal import Decimal
from fastapi import FastAPI, HTTPException, Query, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, ConfigDict
import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv

load_dotenv()

POSTGRES_URL = os.environ.get("POSTGRES_URL") or os.environ.get("DATABASE_URL") or os.environ.get("SUPABASE_DB_URL")

app = FastAPI(title="Expense Tracker API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_db():
    try:
        conn = psycopg2.connect(POSTGRES_URL)
        return conn
    except Exception as e:
        raise HTTPException(
            status_code=500, 
            detail=f"Database connection error: {str(e)}"
        )

# Seed & Ensure tables exist on startup
@app.on_event("startup")
def init_db():
    if not POSTGRES_URL:
        print("WARNING: POSTGRES_URL is not configured in .env!")
        return
    try:
        conn = psycopg2.connect(POSTGRES_URL)
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id VARCHAR(255) PRIMARY KEY,
                email VARCHAR(255) UNIQUE NOT NULL,
                name VARCHAR(255),
                picture TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS expenses (
                id SERIAL PRIMARY KEY,
                user_id VARCHAR(255) NOT NULL,
                amount NUMERIC(12, 2) NOT NULL,
                category VARCHAR(100) NOT NULL,
                description TEXT NOT NULL,
                date DATE NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS loans (
                id SERIAL PRIMARY KEY,
                user_id VARCHAR(255) NOT NULL,
                person VARCHAR(100) NOT NULL,
                direction VARCHAR(8) NOT NULL CHECK (direction IN ('borrowed', 'lent')),
                amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
                date DATE NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                refunded BOOLEAN NOT NULL DEFAULT FALSE,
                refunded_at TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
            CREATE INDEX IF NOT EXISTS loans_user_id_idx ON loans (user_id);
        """)
        conn.commit()
        print("Database schema initialized successfully!")
        
        cur.close()
        conn.close()
    except Exception as e:
        print(f"Error initializing DB: {e}")

# Pydantic Schemas
class ExpenseCreate(BaseModel):
    user_id: str
    amount: float = Field(..., gt=0, description="Expense amount must be positive")
    category: str
    description: str
    date: str  # YYYY-MM-DD

class ExpenseUpdate(BaseModel):
    amount: Optional[float] = None
    category: Optional[str] = None
    description: Optional[str] = None
    date: Optional[str] = None

class GoogleAuthRequest(BaseModel):
    email: str
    name: Optional[str] = "Expense User"
    picture: Optional[str] = None
    sub: Optional[str] = None

class LoanCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    user_id: str = Field(min_length=1)
    person: str = Field(min_length=1, max_length=100)
    direction: Literal['borrowed', 'lent']
    amount: Decimal = Field(gt=0, max_digits=12, decimal_places=2)
    date: date
    note: str = Field(default='', max_length=2000)

class LoanStatus(BaseModel):
    refunded: bool


def serialize_loan(row):
    return {**row, 'amount': float(row['amount'])}


@app.get('/api/loans')
def get_loans(user_id: str = Query(...)):
    conn = get_db()
    try:
        effective_user_id = resolve_user_id(conn, user_id)
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                'SELECT * FROM loans WHERE user_id = %s ORDER BY refunded, date DESC, id DESC;',
                (effective_user_id,),
            )
            return [serialize_loan(row) for row in cur.fetchall()]
    finally:
        conn.close()


@app.post('/api/loans', status_code=201)
def create_loan(loan: LoanCreate):
    conn = get_db()
    try:
        effective_user_id = resolve_user_id(conn, loan.user_id)
        with conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                '''INSERT INTO loans (user_id, person, direction, amount, date, note)
                   VALUES (%s, %s, %s, %s, %s, %s) RETURNING *;''',
                (effective_user_id, loan.person, loan.direction, loan.amount, loan.date, loan.note),
            )
            return serialize_loan(cur.fetchone())
    finally:
        conn.close()


@app.patch('/api/loans/{loan_id}')
def set_loan_status(loan_id: int, payload: LoanStatus, user_id: str = Query(...)):
    conn = get_db()
    try:
        effective_user_id = resolve_user_id(conn, user_id)
        with conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                '''UPDATE loans SET refunded = %s,
                   refunded_at = CASE WHEN %s THEN COALESCE(refunded_at, CURRENT_TIMESTAMP) ELSE NULL END
                   WHERE id = %s AND user_id = %s RETURNING *;''',
                (payload.refunded, payload.refunded, loan_id, effective_user_id),
            )
            row = cur.fetchone()
            if row is None:
                raise HTTPException(status_code=404, detail='Loan not found')
            return serialize_loan(row)
    finally:
        conn.close()


@app.delete('/api/loans/{loan_id}')
def delete_loan(loan_id: int, user_id: str = Query(...)):
    conn = get_db()
    try:
        effective_user_id = resolve_user_id(conn, user_id)
        with conn, conn.cursor() as cur:
            cur.execute('DELETE FROM loans WHERE id = %s AND user_id = %s;', (loan_id, effective_user_id))
            if cur.rowcount == 0:
                raise HTTPException(status_code=404, detail='Loan not found')
        return {'success': True, 'id': loan_id}
    finally:
        conn.close()

# Category Colors Palette
CATEGORY_COLORS = {
    "Gym": "#8b5cf6",
    "Food & Dining": "#f59e0b",
    "Shopping": "#ec4899",
    "Bills & Utilities": "#3b82f6",
    "Transportation": "#10b981",
    "Entertainment": "#6366f1",
    "Health & Fitness": "#14b8a6",
    "Travel": "#06b6d4",
    "Investment": "#22c55e",
    "Education": "#0ea5e9",
    "Others": "#64748b"
}

def resolve_user_id(conn, user_id: str) -> str:
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT id FROM users WHERE id = %s;", (user_id,))
    row = cur.fetchone()
    if row:
        cur.close()
        return row['id']
    cur.execute("SELECT id FROM users ORDER BY created_at ASC LIMIT 1;")
    row = cur.fetchone()
    cur.close()
    if row:
        return row['id']
    return user_id

@app.get("/api/health")
def health_check():
    if not POSTGRES_URL:
        return {"status": "error", "db_connected": False, "detail": "POSTGRES_URL is not set"}
    try:
        conn = psycopg2.connect(POSTGRES_URL, connect_timeout=3)
        conn.close()
        return {"status": "ok", "db_connected": True}
    except Exception as e:
        return {"status": "degraded", "db_connected": False, "detail": str(e)}

@app.post("/api/auth/google")
def google_auth(payload: GoogleAuthRequest):
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    user_id = payload.sub or f"google_{payload.email.split('@')[0]}"
    
    cur.execute("SELECT * FROM users WHERE email = %s;", (payload.email,))
    user = cur.fetchone()
    
    if not user:
        cur.execute(
            "INSERT INTO users (id, email, name, picture) VALUES (%s, %s, %s, %s) RETURNING *;",
            (user_id, payload.email, payload.name, payload.picture)
        )
        user = cur.fetchone()
        conn.commit()
    
    cur.close()
    conn.close()
    return {"user": user}

@app.get("/api/expenses")
def get_expenses(
    user_id: str = Query(...),
    month: Optional[int] = None,
    year: Optional[int] = None,
    category: Optional[str] = None
):
    conn = get_db()
    effective_user_id = resolve_user_id(conn, user_id)
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    query = "SELECT * FROM expenses WHERE user_id = %s"
    params = [effective_user_id]
    
    if year:
        query += " AND EXTRACT(YEAR FROM date) = %s"
        params.append(year)
    if month:
        query += " AND EXTRACT(MONTH FROM date) = %s"
        params.append(month)
    if category and category != "All":
        query += " AND category = %s"
        params.append(category)
        
    query += " ORDER BY date DESC, id DESC;"
    
    cur.execute(query, params)
    expenses = cur.fetchall()
    
    # Format date as string
    for exp in expenses:
        if isinstance(exp['date'], (date, datetime)):
            exp['date'] = exp['date'].strftime('%Y-%m-%d')
        exp['amount'] = float(exp['amount'])
        
    cur.close()
    conn.close()
    return expenses

@app.post("/api/expenses")
def create_expense(expense: ExpenseCreate):
    conn = get_db()
    effective_user_id = resolve_user_id(conn, expense.user_id)
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    try:
        expense_date = datetime.strptime(expense.date, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Expected YYYY-MM-DD.")
        
    cur.execute(
        """
        INSERT INTO expenses (user_id, amount, category, description, date)
        VALUES (%s, %s, %s, %s, %s)
        RETURNING *;
        """,
        (effective_user_id, expense.amount, expense.category, expense.description, expense_date)
    )
    new_expense = cur.fetchone()
    conn.commit()
    
    if isinstance(new_expense['date'], (date, datetime)):
        new_expense['date'] = new_expense['date'].strftime('%Y-%m-%d')
    new_expense['amount'] = float(new_expense['amount'])
    
    cur.close()
    conn.close()
    return new_expense

@app.put("/api/expenses/{expense_id}")
def update_expense(expense_id: int, expense: ExpenseUpdate, user_id: str = Query(...)):
    conn = get_db()
    effective_user_id = resolve_user_id(conn, user_id)
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    cur.execute("SELECT * FROM expenses WHERE id = %s AND user_id = %s;", (expense_id, effective_user_id))
    existing = cur.fetchone()
    if not existing:
        cur.close()
        conn.close()
        raise HTTPException(status_code=404, detail="Expense not found")
        
    updates = []
    params = []
    if expense.amount is not None:
        updates.append("amount = %s")
        params.append(expense.amount)
    if expense.category is not None:
        updates.append("category = %s")
        params.append(expense.category)
    if expense.description is not None:
        updates.append("description = %s")
        params.append(expense.description)
    if expense.date is not None:
        updates.append("date = %s")
        params.append(datetime.strptime(expense.date, "%Y-%m-%d").date())
        
    if not updates:
        cur.close()
        conn.close()
        return existing
        
    params.extend([expense_id, effective_user_id])
    query = f"UPDATE expenses SET {', '.join(updates)} WHERE id = %s AND user_id = %s RETURNING *;"
    
    cur.execute(query, params)
    updated = cur.fetchone()
    conn.commit()
    
    if isinstance(updated['date'], (date, datetime)):
        updated['date'] = updated['date'].strftime('%Y-%m-%d')
    updated['amount'] = float(updated['amount'])
    
    cur.close()
    conn.close()
    return updated

@app.delete("/api/expenses/{expense_id}")
def delete_expense(expense_id: int, user_id: str = Query(...)):
    conn = get_db()
    effective_user_id = resolve_user_id(conn, user_id)
    cur = conn.cursor()
    cur.execute("DELETE FROM expenses WHERE id = %s AND user_id = %s;", (expense_id, effective_user_id))
    deleted = cur.rowcount
    conn.commit()
    cur.close()
    conn.close()
    
    if deleted == 0:
        raise HTTPException(status_code=404, detail="Expense not found")
    return {"success": True, "id": expense_id}

@app.get("/api/dashboard/stats")
def get_dashboard_stats(
    user_id: str = Query(...),
    month: int = Query(..., ge=1, le=12),
    year: int = Query(...)
):
    conn = get_db()
    effective_user_id = resolve_user_id(conn, user_id)
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    # 1. Total Expenses All Time
    cur.execute("SELECT COALESCE(SUM(amount), 0) as total FROM expenses WHERE user_id = %s;", (effective_user_id,))
    total_expenses = float(cur.fetchone()['total'])
    
    # 2. This Month Total
    cur.execute(
        """
        SELECT COALESCE(SUM(amount), 0) as total 
        FROM expenses 
        WHERE user_id = %s AND EXTRACT(MONTH FROM date) = %s AND EXTRACT(YEAR FROM date) = %s;
        """,
        (effective_user_id, month, year)
    )
    this_month_total = float(cur.fetchone()['total'])
    
    # 3. Days in month calculation for Daily Average
    days_in_month = calendar.monthrange(year, month)[1]
    today = date.today()
    if today.year == year and today.month == month:
        elapsed_days = max(1, today.day)
    else:
        elapsed_days = days_in_month
        
    daily_average = round(this_month_total / elapsed_days, 2) if elapsed_days > 0 else 0.0
    
    # 4. Active categories count in this month
    cur.execute(
        """
        SELECT COUNT(DISTINCT category) as cat_count 
        FROM expenses 
        WHERE user_id = %s AND EXTRACT(MONTH FROM date) = %s AND EXTRACT(YEAR FROM date) = %s;
        """,
        (effective_user_id, month, year)
    )
    active_categories_count = int(cur.fetchone()['cat_count'])
    
    # 5. Daily Spending Pattern for Chart
    cur.execute(
        """
        SELECT date, SUM(amount) as daily_total 
        FROM expenses 
        WHERE user_id = %s AND EXTRACT(MONTH FROM date) = %s AND EXTRACT(YEAR FROM date) = %s
        GROUP BY date 
        ORDER BY date ASC;
        """,
        (effective_user_id, month, year)
    )
    daily_rows = {row['date'].strftime('%Y-%m-%d'): float(row['daily_total']) for row in cur.fetchall()}
    
    month_name_short = calendar.month_abbr[month]
    daily_pattern = []
    for day_num in range(1, days_in_month + 1):
        day_str = f"{year:04d}-{month:02d}-{day_num:02d}"
        label = f"{month_name_short} {day_num}"
        amount = daily_rows.get(day_str, 0.0)
        daily_pattern.append({
            "day": label,
            "dayNum": day_num,
            "amount": amount,
            "fullDate": day_str
        })
        
    # 6. Recent Expenses for selected month (up to 5)
    cur.execute(
        """
        SELECT * FROM expenses 
        WHERE user_id = %s AND EXTRACT(MONTH FROM date) = %s AND EXTRACT(YEAR FROM date) = %s
        ORDER BY date DESC, id DESC 
        LIMIT 5;
        """,
        (effective_user_id, month, year)
    )
    recent_expenses = cur.fetchall()
    for exp in recent_expenses:
        if isinstance(exp['date'], (date, datetime)):
            exp['date'] = exp['date'].strftime('%Y-%m-%d')
        exp['amount'] = float(exp['amount'])
        
    # 7. Top Categories in month
    cur.execute(
        """
        SELECT category, SUM(amount) as total, COUNT(*) as count 
        FROM expenses 
        WHERE user_id = %s AND EXTRACT(MONTH FROM date) = %s AND EXTRACT(YEAR FROM date) = %s
        GROUP BY category 
        ORDER BY total DESC;
        """,
        (effective_user_id, month, year)
    )
    top_categories = []
    for row in cur.fetchall():
        cat_name = row['category']
        top_categories.append({
            "category": cat_name,
            "total": float(row['total']),
            "count": int(row['count']),
            "color": CATEGORY_COLORS.get(cat_name, "#8b5cf6")
        })
        
    # 8. Total Expenses by Category in year
    cur.execute(
        """
        SELECT category, SUM(amount) as total, COUNT(*) as count 
        FROM expenses 
        WHERE user_id = %s AND EXTRACT(YEAR FROM date) = %s
        GROUP BY category 
        ORDER BY total DESC;
        """,
        (effective_user_id, year)
    )
    total_by_category = []
    for row in cur.fetchall():
        cat_name = row['category']
        total_by_category.append({
            "category": cat_name,
            "total": float(row['total']),
            "count": int(row['count']),
            "color": CATEGORY_COLORS.get(cat_name, "#8b5cf6")
        })
        
    cur.close()
    conn.close()
    
    return {
        "total_expenses": total_expenses,
        "this_month": this_month_total,
        "daily_average": daily_average,
        "active_categories": active_categories_count,
        "daily_pattern": daily_pattern,
        "recent_expenses": recent_expenses,
        "top_categories": top_categories,
        "total_by_category": total_by_category,
        "month": month,
        "year": year
    }
