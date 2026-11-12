"""
Offline unit tests for 18+ DOB enforcement and Terms version 2026-11-12 in server.py.
Mocks database and config so no external DB or network call is required.
"""

import contextlib
import datetime
import pathlib
import sys
import types
import unittest
from unittest.mock import MagicMock, patch

BACKEND_DIR = pathlib.Path(__file__).resolve().parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))


def _load_server_isolated():
    class _DummyCfg:
        CORS_ORIGINS = ['https://workmate4u.com']
        SECRET_KEY = 'test-secret-key-for-unit-tests-only'
        JWT_SECRET = 'test-jwt-secret-key-for-unit-tests-only'
        JWT_EXPIRATION_HOURS = 24
        SENDGRID_API_KEY = ''
        FROM_EMAIL = 'info@workmate4u.com'
        APP_NAME = 'Workmate4u'
        RAZORPAY_KEY_ID = ''
        RAZORPAY_KEY_SECRET = ''
        RAZORPAY_WEBHOOK_SECRET = ''
        GOOGLE_CLIENT_ID = ''

        def __getattr__(self, _name):
            return ''

    dummy_cfg = _DummyCfg()
    mock_config_mod = types.ModuleType('config')
    mock_config_mod.get_config = lambda: dummy_cfg

    @contextlib.contextmanager
    def _dummy_get_db():
        cur = MagicMock()
        cur.fetchone.return_value = None
        cur.fetchall.return_value = []
        conn = MagicMock()
        yield cur, conn

    mock_db_mod = types.ModuleType('database')
    mock_db_mod.init_db = lambda: None
    mock_db_mod.get_db = _dummy_get_db
    mock_db_mod.dict_from_row = lambda row: row if isinstance(row, dict) else {}
    mock_db_mod.get_placeholder = lambda: '%s'

    with patch.dict(sys.modules, {'config': mock_config_mod, 'database': mock_db_mod}):
        if 'server' in sys.modules:
            del sys.modules['server']
        import server  # type: ignore
        return server


class BackendAgeValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = _load_server_isolated()
        cls.client = cls.server.app.test_client()

    def test_constants_are_18_and_2026_11_12(self):
        self.assertEqual(self.server.MINIMUM_LEGAL_AGE, 18)
        self.assertEqual(self.server.TERMS_VERSION, '2026-11-12')

    def test_validate_adult_dob_edges(self):
        today = datetime.datetime.now(self.server._IST_TZ).date()

        # Exactly 18 today -> accepted
        dob_18_today = today.replace(year=today.year - 18)
        ok, norm, err = self.server.validate_adult_dob(dob_18_today.isoformat())
        self.assertTrue(ok, err)
        self.assertEqual(norm, dob_18_today.isoformat())

        # 1 day short of 18th birthday -> rejected
        dob_under_18 = dob_18_today + datetime.timedelta(days=1)
        ok, _, err = self.server.validate_adult_dob(dob_under_18.isoformat())
        self.assertFalse(ok)
        self.assertIn('18', err)

        # Age 16 -> rejected
        dob_16 = today.replace(year=today.year - 16)
        ok, _, _ = self.server.validate_adult_dob(dob_16.isoformat())
        self.assertFalse(ok)

        # Future or pre-1900 or invalid -> rejected
        ok, _, _ = self.server.validate_adult_dob((today + datetime.timedelta(days=10)).isoformat())
        self.assertFalse(ok)
        ok, _, _ = self.server.validate_adult_dob('1899-05-01')
        self.assertFalse(ok)
        ok, _, _ = self.server.validate_adult_dob('not-a-date')
        self.assertFalse(ok)

    def test_register_rejects_underage_16_and_17(self):
        today = datetime.datetime.now(self.server._IST_TZ).date()
        dob_17 = (today.replace(year=today.year - 18) + datetime.timedelta(days=1)).isoformat()

        with patch.object(self.server, 'get_user_by_email', return_value=None):
            resp = self.client.post('/api/auth/register', json={
                'name': 'Minor Test',
                'email': 'minor@example.com',
                'password': 'Password1',
                'dob': dob_17,
            })
        self.assertEqual(resp.status_code, 400)
        body = resp.get_json()
        self.assertFalse(body['success'])
        self.assertIn('18', body['message'])

    def test_google_auth_rejects_underage_dob(self):
        today = datetime.datetime.now(self.server._IST_TZ).date()
        dob_17 = (today.replace(year=today.year - 18) + datetime.timedelta(days=5)).isoformat()

        resp = self.client.post('/api/auth/google', json={
            'credential': 'dummy-token',
            'dob': dob_17,
        })
        self.assertEqual(resp.status_code, 400)
        body = resp.get_json()
        self.assertFalse(body['success'])
        self.assertIn('18', body['message'])

    def test_profile_update_rejects_underage_dob(self):
        token = self.server.generate_jwt_token('user_123', 'adult@example.com')
        today = datetime.datetime.now(self.server._IST_TZ).date()
        dob_16 = today.replace(year=today.year - 16, day=min(today.day, 28)).isoformat()

        with patch.object(self.server, 'get_user_by_id', return_value={
            'id': 'user_123',
            'email': 'adult@example.com',
            'dob': '1995-05-05',
            'is_banned': False,
        }):
            resp = self.client.put(
                '/api/user/profile',
                headers={'Authorization': f'Bearer {token}'},
                json={'dob': dob_16},
            )
        self.assertEqual(resp.status_code, 400)
        body = resp.get_json()
        self.assertFalse(body['success'])
        self.assertIn('18', body['message'])

    def test_profile_update_blocks_existing_underage_user(self):
        token = self.server.generate_jwt_token('minor_1', 'minor1@example.com')
        today = datetime.datetime.now(self.server._IST_TZ).date()
        dob_16 = today.replace(year=today.year - 16, day=min(today.day, 28)).isoformat()

        with patch.object(self.server, 'get_user_by_id', return_value={
            'id': 'minor_1',
            'email': 'minor1@example.com',
            'dob': dob_16,
            'is_banned': False,
        }):
            resp = self.client.put(
                '/api/user/profile',
                headers={'Authorization': f'Bearer {token}'},
                json={'name': 'Updated Name'},
            )
        self.assertEqual(resp.status_code, 403)
        self.assertIn('18', resp.get_json()['message'])

    def test_login_blocks_confirmed_underage_user(self):
        from werkzeug.security import generate_password_hash
        today = datetime.datetime.now(self.server._IST_TZ).date()
        dob_17 = (today.replace(year=today.year - 18) + datetime.timedelta(days=1)).isoformat()

        with patch.object(self.server, 'get_user_by_email', return_value={
            'id': 'minor_2',
            'email': 'minor2@example.com',
            'password_hash': generate_password_hash('Pass1234', method='pbkdf2:sha256'),
            'dob': dob_17,
            'is_banned': False,
            'auth_provider': 'email',
        }):
            resp = self.client.post('/api/auth/login', json={
                'email': 'minor2@example.com',
                'password': 'Pass1234',
            })
        self.assertEqual(resp.status_code, 403)
        self.assertIn('18', resp.get_json()['message'])


if __name__ == '__main__':
    unittest.main()
