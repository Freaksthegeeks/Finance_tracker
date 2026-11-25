import { useState } from 'react';

const today = () => {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
};

export function LoanSummary({ ledger, formatMoney, onManage }) {
  const outstanding = direction => ledger.loans.filter(loan => !loan.refunded && loan.direction === direction)
    .reduce((sum, loan) => sum + Number(loan.amount), 0);
  return <section className="content-card loan-summary">
    <h2 className="card-title">Borrowed &amp; lent</h2>
    <p className="card-subtitle">Outstanding across all dates · Excluded from expenses</p>
    {ledger.error && <p role="alert" className="loan-error">{ledger.loaded ? 'Showing previous balances. ' : ''}{ledger.error}</p>}
    <div className="loan-balances">
      <div><p>Borrowed · You owe</p><strong>{ledger.loaded ? formatMoney(outstanding('borrowed')) : '—'}</strong></div>
      <div><p>Lent · Owed to you</p><strong>{ledger.loaded ? formatMoney(outstanding('lent')) : '—'}</strong></div>
    </div>
    {onManage && <button className="tab-btn" onClick={onManage}>Manage borrowed &amp; lent</button>}
  </section>;
}

export default function Loans({ ledger, formatMoney }) {
  const [form, setForm] = useState({ person: '', amount: '', direction: 'lent', date: today(), note: '' });
  const [saved, setSaved] = useState(false);
  const change = event => { setSaved(false); setForm({ ...form, [event.target.name]: event.target.value }); };
  const submit = async event => {
    event.preventDefault();
    if (!form.person.trim()) return;
    if (await ledger.mutate('POST', null, { ...form, person: form.person.trim(), amount: Number(form.amount) })) {
      setForm({ person: '', amount: '', direction: 'lent', date: today(), note: '' }); setSaved(true);
    }
  };
  const ordered = [...ledger.loans].sort((a, b) => Number(a.refunded) - Number(b.refunded) || b.date.localeCompare(a.date) || b.id - a.id);
  return <div>
    <LoanSummary ledger={ledger} formatMoney={formatMoney} />
    <section className="content-card">
      <h2 className="card-title">Record borrowed or lent money</h2>
      <form onSubmit={submit} className="loan-form">
        <fieldset disabled={ledger.busy}>
          <label>Type<select name="direction" value={form.direction} onChange={change}>
            <option value="lent">Lent · I gave money</option><option value="borrowed">Borrowed · I received money</option>
          </select></label>
          <label>Person’s name<input name="person" value={form.person} onChange={change} required maxLength={100} pattern=".*\S.*" /></label>
          <label>Amount (₹)<input name="amount" value={form.amount} onChange={change} type="number" required min="0.01" max="9999999999.99" step="0.01" /></label>
          <label>Date<input name="date" value={form.date} onChange={change} type="date" required /></label>
          <label className="loan-note">Note (optional)<input name="note" value={form.note} onChange={change} maxLength={2000} /></label>
          <button className="tab-btn active" type="submit">{ledger.busy ? 'Saving change…' : 'Save entry'}</button>
        </fieldset>
      </form>
      {saved && <p role="status">Entry saved</p>}
    </section>
    <section className="content-card">
      <h2 className="card-title">Entries &amp; repayment history</h2>
      {ordered.length === 0 && <p>{ledger.loaded ? 'No entries yet. Add a person and amount above.' : 'Entries have not loaded yet.'}</p>}
      <div className="loan-entries">{ordered.map(loan => <article key={loan.id} className="loan-entry">
        <div>
          <h3>{loan.refunded ? <s>{loan.person}</s> : loan.person}</h3>
          <p>{loan.direction === 'lent' ? 'Lent' : 'Borrowed'} · {formatMoney(Number(loan.amount))}</p>
          <p><time dateTime={loan.date}>{loan.date}</time></p>
          {loan.note && <p>{loan.note}</p>}
          {loan.refunded && <strong className="loan-refunded">Refunded</strong>}
        </div>
        <div className="loan-actions">
          <button className="tab-btn" disabled={ledger.busy} onClick={() => ledger.mutate('PATCH', loan.id, { refunded: !loan.refunded })}>{loan.refunded ? 'Undo refund' : 'Mark refunded'}</button>
          <button className="tab-btn" disabled={ledger.busy} onClick={() => {
            if (window.confirm(`Delete the entry for ${loan.person}? This also removes it from outstanding balances.`)) ledger.mutate('DELETE', loan.id);
          }}>Delete entry</button>
        </div>
      </article>)}</div>
    </section>
  </div>;
}
