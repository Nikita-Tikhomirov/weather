import os
import unittest
from unittest.mock import Mock, patch

import requests

import telegram_bot as tb


class TelegramBotStartupTests(unittest.TestCase):
    @patch.dict(os.environ, {}, clear=True)
    def test_validate_fails_without_token(self) -> None:
        ok, code, message = tb.validate_bot_startup()
        self.assertFalse(ok)
        self.assertEqual(code, "invalid_token")
        self.assertIn("TELEGRAM_BOT_TOKEN", message)

    @patch.dict(os.environ, {"TELEGRAM_BOT_TOKEN": "demo-token"}, clear=True)
    @patch("telegram_bot.telegram_api", return_value="https://api.telegram.org/botdemo/getMe")
    @patch("telegram_bot.requests.get", side_effect=requests.exceptions.Timeout("timeout"))
    def test_validate_reports_timeout(self, *_mocks) -> None:
        ok, code, message = tb.validate_bot_startup()
        self.assertFalse(ok)
        self.assertEqual(code, "telegram_timeout")
        self.assertIn("Таймаут", message)

    @patch.dict(os.environ, {"TELEGRAM_BOT_TOKEN": "demo-token"}, clear=True)
    @patch("telegram_bot.telegram_api", return_value="https://api.telegram.org/botdemo/getMe")
    @patch("telegram_bot.requests.get")
    def test_validate_reports_invalid_token_on_401(self, mock_get: Mock, *_mocks) -> None:
        response = Mock()
        response.status_code = 401
        response.json.return_value = {"ok": False, "description": "Unauthorized"}
        mock_get.return_value = response

        ok, code, _message = tb.validate_bot_startup()
        self.assertFalse(ok)
        self.assertEqual(code, "invalid_token")

    @patch.dict(os.environ, {"TELEGRAM_BOT_TOKEN": "demo-token"}, clear=True)
    @patch("telegram_bot.telegram_api", return_value="https://api.telegram.org/botdemo/getMe")
    @patch("telegram_bot.requests.get")
    def test_validate_success(self, mock_get: Mock, *_mocks) -> None:
        response = Mock()
        response.status_code = 200
        response.json.return_value = {
            "ok": True,
            "result": {"username": "sample_bot"},
        }
        mock_get.return_value = response

        ok, code, message = tb.validate_bot_startup()
        self.assertTrue(ok)
        self.assertEqual(code, "ok")
        self.assertIn("sample_bot", message)


if __name__ == "__main__":
    unittest.main()
