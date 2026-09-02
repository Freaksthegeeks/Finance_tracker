# 💸 Expense Tracker

A modern, full-stack Expense Tracker web application built with **React**, **FastAPI**, and a **Real-Time Supabase PostgreSQL Database**. It enables users to track, analyze, and manage spending habits with an intuitive interface and visual charts.

---

## 🌟 Key Features

- ⚡ **Real-Time PostgreSQL DB**: Powered by Supabase PostgreSQL configured directly via `.env` (`POSTGRES_URL`).
- 📊 **Interactive Dashboard**:
  - **4 Stat Cards**: *Total Expenses*, *This Month Spending*, *Daily Average*, and *Active Categories*.
  - **Daily Spending Pattern**: Smooth interactive area chart (using Recharts) mapping spending trends throughout the selected month.
  - **Recent Expenses & Top Categories**: Real-time breakdown of latest transactions and top spending categories.
  - **Yearly Category Breakdown**: Summary card with a quick *"View all"* filter trigger.
- 👁️ **Privacy Toggle**: Hide or reveal dollar/rupee figures across all stat cards with a single click.
- ➕ **Add New Expense**:
  - Form with input validation for Amount, Category, Description, and Date.
  - Quick feedback messages and category icons.
- 📋 **All Expenses Management**:
  - Comprehensive expenses table with real-time search filtering by description or category.
  - Interactive **Edit Modal** and **Delete** actions synced directly to the PostgreSQL database.
- 📅 **Flexible Month & Year Filtering**: Switch seamlessly between months and years to inspect historical spending data.

---

## 🛠️ Technology Stack

| Layer | Technology |
| :--- | :--- |
| **Frontend** | React (Vite), Lucide Icons, Recharts, Custom CSS Design System |
| **Backend** | Python 3, FastAPI, Uvicorn, Pydantic |
| **Database** | PostgreSQL (Supabase) via `psycopg2` driver |
| **Environment** | `.env` configuration for DB string (`POSTGRES_URL`) |

---

## 📂 Project Structure

```text
Finance_Tracker/
├── backend/
│   └── main.py              # FastAPI server, REST API, & database operations
├── frontend/
│   ├── src/
│   │   ├── App.jsx          # Main UI application (Dashboard, Add Expense, All Expenses)
│   │   ├── index.css        # Styled design system matching exact screenshots
│   │   └── main.jsx         # React application entry point
│   ├── package.json         # Frontend package dependencies
│   └── vite.config.js       # Vite configuration
├── .env                     # Supabase PostgreSQL database URL configuration
├── .gitignore               # Ignored files (secrets, venv, node_modules, build)
├── requirements.txt         # Python backend dependencies
└── README.md                # Project documentation
```

---

## 🚀 Getting Started

### Prerequisites

- **Docker & Docker Compose** (optional, for containerized execution)
- **Node.js** (v18+ recommended) & **npm**
- **Python** (v3.8+ recommended) & **pip**
- **PostgreSQL Database URL** (configured in `.env`)

---

### 🐋 Running with Docker (Recommended)

1. Ensure your `.env` file is created in the root directory with `POSTGRES_URL`.
2. Build and start containers:
   ```bash
   docker compose up --build
   ```
3. Access services:
   - 🌐 **Frontend**: [http://localhost:3000](http://localhost:3000)
   - ⚡ **Backend API**: [http://localhost:8000](http://localhost:8000)
   - 🔗 **Swagger Docs**: [http://localhost:8000/docs](http://localhost:8000/docs)

---

### 1. Database Configuration (`.env`)

Ensure the `.env` file in the root directory contains your Supabase PostgreSQL connection string:

```env
POSTGRES_URL=postgresql://postgres:<password>@db.<project-ref>.supabase.co:5432/postgres
```

---

### 2. Start the Backend API

1. Navigate to the `backend` directory:
   ```bash
   cd backend
   ```
2. Install Python dependencies:
   ```bash
   pip install -r ../requirements.txt
   ```
3. Start the FastAPI server:
   ```bash
   python -m uvicorn main:app --reload --port 8000
   ```
4. Backend API interactive documentation will be live at:
   - 🔗 **Swagger UI**: [http://localhost:8000/docs](http://localhost:8000/docs)

---

### 3. Start the Frontend Application

1. Open a new terminal and navigate to the `frontend` directory:
   ```bash
   cd frontend
   ```
2. Install Node dependencies:
   ```bash
   npm install
   ```
3. Start the Vite development server:
   ```bash
   npm run dev
   ```
4. Access the web app in your browser:
   - 🌐 **Web App**: [http://localhost:5173](http://localhost:5173)

---

## 📝 API Endpoints Summary

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/api/health` | Health check & DB connection status |
| `POST` | `/api/auth/google` | Google authentication & user profile sync |
| `GET` | `/api/dashboard/stats` | Fetches aggregated statistics & chart data |
| `GET` | `/api/expenses` | Fetches expenses list filtered by user, month, & year |
| `POST` | `/api/expenses` | Adds a new expense record to PostgreSQL |
| `PUT` | `/api/expenses/{id}` | Updates an existing expense |
| `DELETE` | `/api/expenses/{id}` | Deletes an expense record |

---

## 🎨 Design & Aesthetics

The application layout has been created to replicate the clean UI design from the provided reference screenshots:
- Soft off-white background (`#f6f8fa`) with crisp rounded white cards (`#ffffff`).
- Sage green primary action button (`#5c9c84`).
- Rounded pill badge navigation tabs (`Dashboard`, `Add Expense`, `All Expenses`).
- Custom typography using *Plus Jakarta Sans* / *Inter*.

---
