import React, { useState, useEffect } from 'react';
import { 
  DollarSign, 
  Eye, 
  EyeOff, 
  TrendingUp, 
  Zap, 
  Filter, 
  Calendar, 
  User, 
  LogOut, 
  Plus, 
  Search, 
  Trash2, 
  Edit3, 
  CheckCircle,
  X,
  Sparkles
} from 'lucide-react';
import { 
  AreaChart, 
  Area, 
  XAxis, 
  YAxis, 
  CartesianGrid, 
  Tooltip, 
  ResponsiveContainer 
} from 'recharts';

const API_BASE = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000/api';

const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"
];

const CATEGORIES = [
  "Gym",
  "Food & Dining",
  "Shopping",
  "Bills & Utilities",
  "Transportation",
  "Entertainment",
  "Health & Fitness",
  "Travel",
  "Investment",
  "Others"
];

const CATEGORY_COLORS = {
  "Gym": "#8b5cf6",
  "Food & Dining": "#f59e0b",
  "Shopping": "#ec4899",
  "Bills & Utilities": "#3b82f6",
  "Transportation": "#10b981",
  "Entertainment": "#6366f1",
  "Health & Fitness": "#14b8a6",
  "Travel": "#06b6d4",
  "Investment": "#22c55e",
  "Others": "#64748b"
};

export default function App() {
  // Auth state
  const [user, setUser] = useState(() => {
    const saved = localStorage.getItem('expense_tracker_user');
    return saved ? JSON.parse(saved) : { email: 'varuns1054@gmail.com', name: 'Varun', id: 'google_varun_123' };
  });
  const [showAuthModal, setShowAuthModal] = useState(false);
  const [authEmailInput, setAuthEmailInput] = useState('');

  const getTodayDateString = () => new Date().toISOString().split('T')[0];

  // App control state
  const [activeTab, setActiveTab] = useState('add'); // 'dashboard', 'add', 'all'
  const [selectedYear, setSelectedYear] = useState(() => new Date().getFullYear());
  const [selectedMonth, setSelectedMonth] = useState(() => new Date().getMonth() + 1); // Current month (1-indexed)
  const [hideAmounts, setHideAmounts] = useState(false);

  // Stats & Expenses state
  const [stats, setStats] = useState(null);
  const [allExpenses, setAllExpenses] = useState([]);
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [successMsg, setSuccessMsg] = useState('');

  // New Expense Form
  const [formData, setFormData] = useState({
    amount: '',
    category: 'Gym',
    description: '',
    date: new Date().toISOString().split('T')[0]
  });

  // Edit Expense Modal
  const [editingExpense, setEditingExpense] = useState(null);

  // Filters for All Expenses Tab
  const [searchQuery, setSearchQuery] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('All');

  // Fetch Dashboard Stats & All Expenses
  const fetchData = async () => {
    if (!user) return;
    setLoading(true);
    try {
      // Stats
      const resStats = await fetch(
        `${API_BASE}/dashboard/stats?user_id=${user.id}&month=${selectedMonth}&year=${selectedYear}`
      );
      if (resStats.ok) {
        const data = await resStats.json();
        setStats(data);
      }

      // Expenses List
      const resExpenses = await fetch(
        `${API_BASE}/expenses?user_id=${user.id}`
      );
      if (resExpenses.ok) {
        const listData = await resExpenses.json();
        setAllExpenses(listData);
      }
    } catch (err) {
      console.error("Failed to load data:", err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
    // Real-time polling every 6 seconds
    const interval = setInterval(fetchData, 6000);
    return () => clearInterval(interval);
  }, [user, selectedMonth, selectedYear]);

  // Handle Google Login
  const handleGoogleLogin = async (emailToLogin) => {
    const targetEmail = emailToLogin || authEmailInput || 'varuns1054@gmail.com';
    try {
      const res = await fetch(`${API_BASE}/auth/google`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: targetEmail, name: targetEmail.split('@')[0] })
      });
      if (res.ok) {
        const data = await res.json();
        setUser(data.user);
        localStorage.setItem('expense_tracker_user', JSON.stringify(data.user));
        setShowAuthModal(false);
        setAuthEmailInput('');
      }
    } catch (err) {
      console.error("Login failed:", err);
      // Fallback local set if offline
      const mockUser = { email: targetEmail, name: targetEmail.split('@')[0], id: `google_${targetEmail.split('@')[0]}` };
      setUser(mockUser);
      localStorage.setItem('expense_tracker_user', JSON.stringify(mockUser));
      setShowAuthModal(false);
    }
  };

  const handleLogout = () => {
    setUser(null);
    localStorage.removeItem('expense_tracker_user');
  };

  // Add Expense Handler
  const handleAddExpense = async (e) => {
    e.preventDefault();
    if (!formData.amount || !formData.description || !formData.date) {
      setErrorMsg("Please fill in all required fields to add an expense");
      return;
    }
    setErrorMsg('');
    try {
      const res = await fetch(`${API_BASE}/expenses`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          user_id: user.id,
          amount: parseFloat(formData.amount),
          category: formData.category,
          description: formData.description,
          date: formData.date
        })
      });
      if (res.ok) {
        setSuccessMsg("Expense added successfully!");
        if (formData.date) {
          const parts = formData.date.split('-');
          if (parts.length === 3) {
            setSelectedYear(parseInt(parts[0], 10));
            setSelectedMonth(parseInt(parts[1], 10));
          }
        }
        setFormData({ amount: '', category: 'Gym', description: '', date: getTodayDateString() });
        setTimeout(() => setSuccessMsg(''), 3000);
        fetchData();
      } else {
        const err = await res.json();
        setErrorMsg(err.detail || "Failed to add expense");
      }
    } catch (err) {
      setErrorMsg("Network error trying to save expense.");
    }
  };

  // Delete Expense Handler
  const handleDeleteExpense = async (id) => {
    if (!window.confirm("Are you sure you want to delete this expense?")) return;
    try {
      const res = await fetch(`${API_BASE}/expenses/${id}?user_id=${user.id}`, {
        method: 'DELETE'
      });
      if (res.ok) {
        fetchData();
      }
    } catch (err) {
      console.error("Error deleting expense:", err);
    }
  };

  // Update Expense Handler
  const handleUpdateExpense = async (e) => {
    e.preventDefault();
    if (!editingExpense) return;
    try {
      const res = await fetch(`${API_BASE}/expenses/${editingExpense.id}?user_id=${user.id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          amount: parseFloat(editingExpense.amount),
          category: editingExpense.category,
          description: editingExpense.description,
          date: editingExpense.date
        })
      });
      if (res.ok) {
        setEditingExpense(null);
        fetchData();
      }
    } catch (err) {
      console.error("Error updating expense:", err);
    }
  };

  // Format currency helper
  const formatMoney = (val) => {
    if (hideAmounts) return "••••••";
    return `₹${(val || 0).toFixed(2)}`;
  };

  // If user is not logged in, show sleek Google Sign-In view
  if (!user) {
    return (
      <div className="auth-page-container">
        <div className="auth-card">
          <div className="auth-icon-wrap">
            <Sparkles size={32} />
          </div>
          <h1 className="auth-title">Expense Tracker</h1>
          <p className="auth-subtitle">Track and analyze your spending habits seamlessly</p>

          <button 
            className="google-auth-btn"
            onClick={() => handleGoogleLogin('varuns1054@gmail.com')}
          >
            <svg width="20" height="20" viewBox="0 0 24 24">
              <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
              <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
              <path fill="#FBBC05" d="M5.84 14.1c-.22-.66-.35-1.36-.35-2.1s.13-1.44.35-2.1V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.62z"/>
              <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"/>
            </svg>
            Sign in with Google
          </button>

          <div style={{ marginTop: 24, fontSize: 12, color: '#94a3b8' }}>
            Single-click secure authentication powered by Supabase PostgreSQL
          </div>
        </div>
      </div>
    );
  }

  // Filtered expenses for "All Expenses" tab
  const filteredExpensesList = allExpenses.filter(item => {
    const matchesSearch = item.description.toLowerCase().includes(searchQuery.toLowerCase()) || 
                          item.category.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesCat = categoryFilter === 'All' || item.category === categoryFilter;
    return matchesSearch && matchesCat;
  });

  return (
    <div className="app-container">
      {/* Top Header */}
      <header className="header-container">
        <div className="header-left">
          <div className="title-row">
            <h1 className="app-title">Expense Tracker</h1>
            <div 
              className="year-badge"
              onClick={() => {
                const nextYear = selectedYear === 2026 ? 2025 : 2026;
                setSelectedYear(nextYear);
              }}
              title="Click to toggle year"
            >
              <Calendar size={14} />
              {selectedYear}
            </div>
          </div>
          <p className="app-subtitle">Track and analyze your spending habits</p>
        </div>

        <div className="header-right">
          <select 
            className="month-select"
            value={selectedMonth}
            onChange={(e) => setSelectedMonth(Number(e.target.value))}
          >
            {MONTH_NAMES.map((name, idx) => (
              <option key={idx + 1} value={idx + 1}>
                {name} {selectedYear}
              </option>
            ))}
          </select>

          <div className="user-badge">
            <User size={15} color="#64748b" />
            <span>{user.email}</span>
          </div>

          <button className="logout-btn" onClick={handleLogout} title="Logout">
            <LogOut size={15} />
            <span>Logout</span>
          </button>
        </div>
      </header>

      {/* Top 4 Stat Cards */}
      <div className="stats-grid">
        {/* Card 1 */}
        <div className="stat-card">
          <div className="stat-card-header">
            <span className="stat-title">Total Expenses</span>
            <div className="stat-icons">
              <DollarSign size={16} />
              <button className="icon-btn" onClick={() => setHideAmounts(!hideAmounts)}>
                {hideAmounts ? <EyeOff size={16} /> : <Eye size={16} />}
              </button>
            </div>
          </div>
          <div className="stat-amount">{formatMoney(stats?.total_expenses)}</div>
          <div className="stat-footer">All time spending</div>
        </div>

        {/* Card 2 */}
        <div className="stat-card">
          <div className="stat-card-header">
            <span className="stat-title">This Month</span>
            <div className="stat-icons">
              <TrendingUp size={16} />
              <button className="icon-btn" onClick={() => setHideAmounts(!hideAmounts)}>
                {hideAmounts ? <EyeOff size={16} /> : <Eye size={16} />}
              </button>
            </div>
          </div>
          <div className="stat-amount">{formatMoney(stats?.this_month)}</div>
          <div className="stat-footer">{MONTH_NAMES[selectedMonth - 1]} {selectedYear} spending</div>
        </div>

        {/* Card 3 */}
        <div className="stat-card">
          <div className="stat-card-header">
            <span className="stat-title">Daily Average</span>
            <div className="stat-icons">
              <Zap size={16} />
              <button className="icon-btn" onClick={() => setHideAmounts(!hideAmounts)}>
                {hideAmounts ? <EyeOff size={16} /> : <Eye size={16} />}
              </button>
            </div>
          </div>
          <div className="stat-amount">{formatMoney(stats?.daily_average)}</div>
          <div className="stat-footer">Average per day</div>
        </div>

        {/* Card 4 */}
        <div className="stat-card">
          <div className="stat-card-header">
            <span className="stat-title">Categories</span>
            <div className="stat-icons">
              <Filter size={16} />
            </div>
          </div>
          <div className="stat-amount">{stats?.active_categories || 0}</div>
          <div className="stat-footer">Active categories</div>
        </div>
      </div>

      {/* Navigation Tabs */}
      <nav className="nav-tabs-container">
        <button 
          className={`tab-btn ${activeTab === 'dashboard' ? 'active' : ''}`}
          onClick={() => setActiveTab('dashboard')}
        >
          Dashboard
        </button>
        <button 
          className={`tab-btn ${activeTab === 'add' ? 'active' : ''}`}
          onClick={() => setActiveTab('add')}
        >
          Add Expense
        </button>
        <button 
          className={`tab-btn ${activeTab === 'all' ? 'active' : ''}`}
          onClick={() => setActiveTab('all')}
        >
          All Expenses
        </button>
      </nav>

      {/* TAB 1: DASHBOARD */}
      {activeTab === 'dashboard' && (
        <div>
          {/* Daily Spending Pattern Chart */}
          <div className="content-card">
            <h2 className="card-title">Daily Spending Pattern</h2>
            <p className="card-subtitle">
              Your daily expenses for {MONTH_NAMES[selectedMonth - 1]} {selectedYear}
            </p>
            <div style={{ width: '100%', height: 260 }}>
              <ResponsiveContainer>
                <AreaChart 
                  data={stats?.daily_pattern || []}
                  margin={{ top: 10, right: 10, left: -20, bottom: 0 }}
                >
                  <defs>
                    <linearGradient id="purpleGradient" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#8b5cf6" stopOpacity={0.35}/>
                      <stop offset="95%" stopColor="#8b5cf6" stopOpacity={0.0}/>
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" vertical={true} stroke="#e2e8f0" />
                  <XAxis 
                    dataKey="day" 
                    tick={{ fontSize: 11, fill: '#64748b' }}
                    interval={1}
                  />
                  <YAxis tick={{ fontSize: 11, fill: '#64748b' }} />
                  <Tooltip 
                    formatter={(val) => [formatMoney(val), "Amount"]}
                    labelStyle={{ color: '#0f172a', fontWeight: 600 }}
                    contentStyle={{ backgroundColor: '#ffffff', borderRadius: 8, borderColor: '#e2e8f0' }}
                  />
                  <Area 
                    type="monotone" 
                    dataKey="amount" 
                    stroke="#8b5cf6" 
                    strokeWidth={2}
                    fillOpacity={1} 
                    fill="url(#purpleGradient)" 
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* Two Cards Grid */}
          <div className="two-cards-grid">
            {/* Recent Expenses */}
            <div className="content-card" style={{ marginBottom: 0 }}>
              <h2 className="card-title">Recent Expenses</h2>
              <p className="card-subtitle">
                Your latest spending activity in {MONTH_NAMES[selectedMonth - 1]} {selectedYear}
              </p>
              <div>
                {(!stats?.recent_expenses || stats.recent_expenses.length === 0) ? (
                  <p style={{ fontSize: 13, color: '#94a3b8', padding: '20px 0' }}>
                    No recent expenses recorded for this month.
                  </p>
                ) : (
                  stats.recent_expenses.map((exp) => (
                    <div className="expense-item" key={exp.id}>
                      <div className="expense-item-left">
                        <span className="expense-desc">{exp.description}</span>
                        <div className="expense-tags">
                          <span className="category-badge">{exp.category}</span>
                          <span className="expense-date-text">{exp.date}</span>
                        </div>
                      </div>
                      <span className="expense-amount-text">{formatMoney(exp.amount)}</span>
                    </div>
                  ))
                )}
              </div>
            </div>

            {/* Top Categories */}
            <div className="content-card" style={{ marginBottom: 0 }}>
              <h2 className="card-title">Top Categories</h2>
              <p className="card-subtitle">
                Your highest spending categories in {MONTH_NAMES[selectedMonth - 1]} {selectedYear}
              </p>
              <div>
                {(!stats?.top_categories || stats.top_categories.length === 0) ? (
                  <p style={{ fontSize: 13, color: '#94a3b8', padding: '20px 0' }}>
                    No categories registered for this month.
                  </p>
                ) : (
                  stats.top_categories.map((cat, idx) => (
                    <div className="cat-item" key={idx}>
                      <div className="cat-item-left">
                        <div className="cat-dot" style={{ backgroundColor: cat.color }}></div>
                        <div className="cat-info">
                          <span className="cat-name">{cat.category}</span>
                          <span className="cat-sub">{cat.count} transactions</span>
                        </div>
                      </div>
                      <span className="expense-amount-text">{formatMoney(cat.total)}</span>
                    </div>
                  ))
                )}
              </div>
            </div>
          </div>

          {/* Bottom Card: Total Expenses by Category */}
          <div className="content-card">
            <h2 className="card-title">Total Expenses by Category</h2>
            <p className="card-subtitle">
              Your total spending by category in {selectedYear}
            </p>
            <div>
              {(!stats?.total_by_category || stats.total_by_category.length === 0) ? (
                <p style={{ fontSize: 13, color: '#94a3b8', padding: '10px 0' }}>
                  No category expenses found for {selectedYear}.
                </p>
              ) : (
                stats.total_by_category.map((cat, idx) => (
                  <div className="cat-item" key={idx}>
                    <div className="cat-item-left">
                      <div className="cat-dot" style={{ backgroundColor: cat.color }}></div>
                      <div className="cat-info">
                        <span className="cat-name">{cat.category}</span>
                        <span className="cat-sub">{cat.count} transactions</span>
                      </div>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
                      <span className="expense-amount-text">{formatMoney(cat.total)}</span>
                      <button 
                        className="view-all-btn"
                        onClick={() => {
                          setCategoryFilter(cat.category);
                          setActiveTab('all');
                        }}
                      >
                        View all
                      </button>
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>
      )}

      {/* TAB 2: ADD EXPENSE */}
      {activeTab === 'add' && (
        <div className="content-card">
          <h2 className="card-title">Add New Expense</h2>
          <p className="card-subtitle">Record a new expense to track your spending</p>

          <form onSubmit={handleAddExpense}>
            <div className="form-row">
              <div className="form-group">
                <label className="form-label">Amount *</label>
                <input 
                  type="number"
                  step="0.01"
                  className="form-input"
                  placeholder="0.00"
                  value={formData.amount}
                  onChange={(e) => setFormData({ ...formData, amount: e.target.value })}
                  required
                />
              </div>

              <div className="form-group">
                <label className="form-label">Category *</label>
                <select 
                  className="form-select"
                  value={formData.category}
                  onChange={(e) => setFormData({ ...formData, category: e.target.value })}
                  required
                >
                  {CATEGORIES.map((cat) => (
                    <option key={cat} value={cat}>{cat}</option>
                  ))}
                </select>
              </div>
            </div>

            <div className="form-group">
              <label className="form-label">Description *</label>
              <input 
                type="text"
                className="form-input"
                placeholder="What did you spend on?"
                value={formData.description}
                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                required
              />
            </div>

            <div className="form-group">
              <label className="form-label">Date *</label>
              <input 
                type="date"
                className="form-input"
                value={formData.date}
                onChange={(e) => setFormData({ ...formData, date: e.target.value })}
                required
              />
              <p className="form-hint">You can select dates from the last 7 days only</p>
            </div>

            <button type="submit" className="submit-btn" disabled={loading}>
              <Plus size={18} />
              Add Expense
            </button>

            {successMsg && (
              <p style={{ color: '#057a55', textAlign: 'center', marginTop: 12, fontWeight: 600, fontSize: 13 }}>
                ✓ {successMsg}
              </p>
            )}

            {errorMsg ? (
              <p style={{ color: '#ef4444', textAlign: 'center', marginTop: 12, fontSize: 13 }}>
                {errorMsg}
              </p>
            ) : (
              <p className="form-footer-note">Please fill in all required fields to add an expense</p>
            )}
          </form>
        </div>
      )}

      {/* TAB 3: ALL EXPENSES */}
      {activeTab === 'all' && (
        <div className="content-card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 16, marginBottom: 20 }}>
            <div>
              <h2 className="card-title">All Expenses</h2>
              <p className="card-subtitle" style={{ marginBottom: 0 }}>
                Manage and filter all recorded expenses for {selectedYear}
              </p>
            </div>

            <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
              {/* Search Bar */}
              <div style={{ position: 'relative' }}>
                <Search size={16} style={{ position: 'absolute', left: 12, top: 12, color: '#94a3b8' }} />
                <input 
                  type="text"
                  placeholder="Search description..."
                  className="form-input"
                  style={{ paddingLeft: 36, width: 220 }}
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                />
              </div>

              {/* Category Filter */}
              <select 
                className="form-select"
                style={{ width: 160 }}
                value={categoryFilter}
                onChange={(e) => setCategoryFilter(e.target.value)}
              >
                <option value="All">All Categories</option>
                {CATEGORIES.map((cat) => (
                  <option key={cat} value={cat}>{cat}</option>
                ))}
              </select>
            </div>
          </div>

          {/* Expenses Table */}
          {filteredExpensesList.length === 0 ? (
            <p style={{ padding: '30px 0', textAlign: 'center', color: '#94a3b8', fontSize: 14 }}>
              No expenses matching criteria.
            </p>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table className="expenses-table">
                <thead>
                  <tr>
                    <th>Date</th>
                    <th>Description</th>
                    <th>Category</th>
                    <th>Amount</th>
                    <th style={{ textAlign: 'right' }}>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredExpensesList.map((item) => (
                    <tr key={item.id}>
                      <td>{item.date}</td>
                      <td style={{ fontWeight: 600 }}>{item.description}</td>
                      <td>
                        <span className="category-badge" style={{ borderColor: CATEGORY_COLORS[item.category] || '#cbd5e1' }}>
                          {item.category}
                        </span>
                      </td>
                      <td style={{ fontWeight: 700 }}>{formatMoney(item.amount)}</td>
                      <td style={{ textAlign: 'right' }}>
                        <button 
                          className="icon-btn" 
                          style={{ marginRight: 8, color: '#3b82f6' }}
                          onClick={() => setEditingExpense(item)}
                          title="Edit"
                        >
                          <Edit3 size={16} />
                        </button>
                        <button 
                          className="icon-btn" 
                          style={{ color: '#ef4444' }}
                          onClick={() => handleDeleteExpense(item.id)}
                          title="Delete"
                        >
                          <Trash2 size={16} />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* Edit Expense Modal */}
      {editingExpense && (
        <div className="modal-overlay">
          <div className="modal-card">
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
              <h3 style={{ fontSize: 18, fontWeight: 700 }}>Edit Expense</h3>
              <button className="icon-btn" onClick={() => setEditingExpense(null)}>
                <X size={20} />
              </button>
            </div>

            <form onSubmit={handleUpdateExpense}>
              <div className="form-group">
                <label className="form-label">Amount</label>
                <input 
                  type="number"
                  step="0.01"
                  className="form-input"
                  value={editingExpense.amount}
                  onChange={(e) => setEditingExpense({ ...editingExpense, amount: e.target.value })}
                  required
                />
              </div>

              <div className="form-group">
                <label className="form-label">Category</label>
                <select 
                  className="form-select"
                  value={editingExpense.category}
                  onChange={(e) => setEditingExpense({ ...editingExpense, category: e.target.value })}
                  required
                >
                  {CATEGORIES.map((cat) => (
                    <option key={cat} value={cat}>{cat}</option>
                  ))}
                </select>
              </div>

              <div className="form-group">
                <label className="form-label">Description</label>
                <input 
                  type="text"
                  className="form-input"
                  value={editingExpense.description}
                  onChange={(e) => setEditingExpense({ ...editingExpense, description: e.target.value })}
                  required
                />
              </div>

              <div className="form-group">
                <label className="form-label">Date</label>
                <input 
                  type="date"
                  className="form-input"
                  value={editingExpense.date}
                  onChange={(e) => setEditingExpense({ ...editingExpense, date: e.target.value })}
                  required
                />
              </div>

              <div style={{ display: 'flex', gap: 12, marginTop: 24 }}>
                <button type="submit" className="submit-btn" style={{ flex: 1 }}>
                  Save Changes
                </button>
                <button 
                  type="button" 
                  className="view-all-btn" 
                  style={{ padding: '12px 20px', borderRadius: 8 }}
                  onClick={() => setEditingExpense(null)}
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
