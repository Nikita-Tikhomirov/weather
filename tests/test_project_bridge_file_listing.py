import tempfile
import unittest
from pathlib import Path

from project_bridge import TunnelClient


class ProjectBridgeFileListingTests(unittest.TestCase):
    def test_list_files_skips_dependency_and_build_directories(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "lib").mkdir()
            (root / "lib" / "main.dart").write_text("void main() {}\n", encoding="utf-8")
            (root / "node_modules").mkdir()
            (root / "node_modules" / "package.json").write_text("{}", encoding="utf-8")
            (root / ".dart_tool").mkdir()
            (root / ".dart_tool" / "state").write_text("cache", encoding="utf-8")
            (root / "build").mkdir()
            (root / "build" / "artifact.txt").write_text("cache", encoding="utf-8")

            client = TunnelClient("127.0.0.1")
            result = client._list_files(
                "weather",
                str(root),
                {"type": "list_files", "path": "", "recursive": True},
            )

            names = {item["name"] for item in result["files"]}
            self.assertIn("lib", names)
            self.assertNotIn("node_modules", names)
            self.assertNotIn(".dart_tool", names)
            self.assertNotIn("build", names)


if __name__ == "__main__":
    unittest.main()
