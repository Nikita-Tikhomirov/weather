import os
import unittest

import sync_runtime


class SyncRuntimeTests(unittest.TestCase):
    def test_backend_api_key_falls_back_to_dev_local(self) -> None:
        original_key = os.environ.get("TODO_BACKEND_API_KEY")
        if "TODO_BACKEND_API_KEY" in os.environ:
            del os.environ["TODO_BACKEND_API_KEY"]
        try:
            runtime = sync_runtime.get_sync_runtime()
        finally:
            if original_key is None:
                os.environ.pop("TODO_BACKEND_API_KEY", None)
            else:
                os.environ["TODO_BACKEND_API_KEY"] = original_key
        self.assertEqual(runtime["backend_api_key"], "dev-local-key")


if __name__ == "__main__":
    unittest.main()
