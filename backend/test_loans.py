"""Loan route contract tests against an isolated SQLite database; no live DB access."""
import sqlite3
import asyncio
import unittest
from unittest.mock import patch

import httpx
from backend import main


class Client:
    def request(self, method, path, **kwargs):
        async def send():
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=main.app), base_url='http://test') as client:
                return await client.request(method, path, **kwargs)
        return asyncio.run(send())

    def get(self, path):
        return self.request('GET', path)

    def post(self, path, **kwargs):
        return self.request('POST', path, **kwargs)

    def patch(self, path, **kwargs):
        return self.request('PATCH', path, **kwargs)

    def delete(self, path):
        return self.request('DELETE', path)


class Cursor:
    def __init__(self, db):
        self.cursor = db.cursor()

    def execute(self, sql, params=()):
        self.cursor.execute(sql.replace('%s', '?'), tuple(str(v) if isinstance(v, main.Decimal) else v for v in params))

    def fetchone(self):
        row = self.cursor.fetchone()
        return dict(row) if row is not None else None

    def fetchall(self):
        return [dict(row) for row in self.cursor.fetchall()]

    @property
    def rowcount(self):
        return self.cursor.rowcount

    def close(self):
        self.cursor.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


class Connection:
    def __init__(self, db):
        self.db = db

    def cursor(self, **kwargs):
        return Cursor(self.db)

    def close(self):
        pass  # Keep the isolated test database alive across API calls.

    def __enter__(self):
        return self

    def __exit__(self, kind, *args):
        self.db.rollback() if kind else self.db.commit()


class LoanRoutesTest(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:', check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.executescript('''
            CREATE TABLE users (id TEXT PRIMARY KEY, created_at TEXT);
            INSERT INTO users VALUES ('owner', '2026-01-01'), ('other', '2026-01-02');
            CREATE TABLE expenses (user_id TEXT, amount NUMERIC);
            INSERT INTO expenses VALUES ('owner', 125.50);
            CREATE TABLE loans (id INTEGER PRIMARY KEY, user_id TEXT, person TEXT,
                direction TEXT, amount NUMERIC, date TEXT, note TEXT,
                refunded BOOLEAN DEFAULT FALSE, refunded_at TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP);
        ''')
        self.mock_db = patch.object(main, 'get_db', return_value=Connection(self.db))
        self.mock_db.start()
        self.client = Client()

    def tearDown(self):
        self.mock_db.stop()
        self.db.close()

    def create(self, **overrides):
        return self.client.post('/api/loans', json={
            'user_id': 'owner', 'person': ' Alex ', 'direction': 'lent',
            'amount': 500.25, 'date': '2026-11-25', **overrides,
        })

    def test_edit_loan_preserves_settlement_and_enforces_owner(self):
        entry = dict(person='Alex', direction='lent', amount='40.50',
                     date='2026-11-01', note='Lunch')
        created = self.client.post('/api/loans', json={**entry, 'user_id': 'owner'})
        self.assertEqual(created.status_code, 201)
        path = f"/api/loans/{created.json()['id']}"
        settled = self.client.patch(f'{path}?user_id=owner', json={'refunded': True})
        self.assertEqual(settled.status_code, 200)
        edited = {**entry, 'person': 'Sam', 'direction': 'borrowed'}
        for owner, body, status in [
            ('other', edited, 404),
            ('owner', {**edited, 'amount': '0'}, 422),
            ('owner', edited, 200),
        ]:
            result = self.client.request('PUT', f'{path}?user_id={owner}', json=body)
            self.assertEqual(result.status_code, status)
        self.assertEqual(result.json()['person'], 'Sam')
        self.assertTrue(result.json()['refunded'])
        self.assertEqual(result.json()['refunded_at'], settled.json()['refunded_at'])

    def test_refund_history_undo_and_expense_isolation(self):
        response = self.create()
        self.assertEqual(response.status_code, 201, response.text)
        loan = response.json()
        self.assertEqual(loan['person'], 'Alex')
        self.assertEqual(loan['amount'], 500.25)
        self.create(direction='borrowed', person='Sam', amount=200)
        url = f"/api/loans/{loan['id']}?user_id=owner"
        refunded = self.client.patch(url, json={'refunded': True}).json()
        repeated = self.client.patch(url, json={'refunded': True}).json()
        self.assertTrue(refunded['refunded'])
        self.assertIsNotNone(refunded['refunded_at'])
        self.assertEqual(refunded['refunded_at'], repeated['refunded_at'])
        history = self.client.get('/api/loans?user_id=owner').json()
        self.assertEqual(len(history), 2)
        self.assertEqual(sum(item['amount'] for item in history if not item['refunded'] and item['direction'] == 'lent'), 0)
        reopened = self.client.patch(url, json={'refunded': False}).json()
        self.assertFalse(reopened['refunded'])
        self.assertIsNone(reopened['refunded_at'])
        self.assertEqual(self.db.execute('SELECT SUM(amount) FROM expenses').fetchone()[0], 125.50)
        self.assertEqual(self.client.delete(url).status_code, 200)
        self.assertEqual(self.client.delete(url).status_code, 404)

    def test_loan_reads_and_writes_are_scoped_to_the_resolved_profile(self):
        loan = self.create().json()
        self.assertEqual(self.client.get('/api/loans?user_id=other').json(), [])
        url = f"/api/loans/{loan['id']}?user_id=other"
        self.assertEqual(self.client.patch(url, json={'refunded': True}).status_code, 404)
        self.assertEqual(self.client.delete(url).status_code, 404)
        self.assertEqual(len(self.client.get('/api/loans?user_id=owner').json()), 1)

    def test_invalid_money_names_types_and_dates_are_rejected(self):
        for fields in [{'amount': 0}, {'amount': -1}, {'amount': 'NaN'},
                       {'amount': '12.345'}, {'amount': '10000000000'},
                       {'person': '  '}, {'direction': 'expense'}, {'date': '2026-02-30'}]:
            with self.subTest(fields=fields):
                self.assertEqual(self.create(**fields).status_code, 422)


if __name__ == '__main__':
    unittest.main()
