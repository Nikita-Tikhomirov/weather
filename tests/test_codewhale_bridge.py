import tempfile
import unittest
from pathlib import Path

from codewhale_bridge import WorkspaceRegistry


class WorkspaceRegistryTests(unittest.TestCase):
    def test_create_workspace_under_desktop(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            desktop = root / "Desktop"
            state = root / "state"
            registry = WorkspaceRegistry(desktop, state)

            workspace = registry.create_workspace("Мой проект")

            self.assertEqual(workspace["name"], "Мой проект")
            self.assertTrue(Path(workspace["path"]).exists())
            self.assertTrue(Path(workspace["path"]).is_dir())
            self.assertEqual(Path(workspace["path"]).parent, desktop)
            self.assertEqual(workspace["status"], "available")
            self.assertEqual(len(registry.list_workspaces()), 1)

    def test_attach_rejects_path_outside_desktop(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            desktop = root / "Desktop"
            outside = root / "Outside"
            outside.mkdir(parents=True)
            registry = WorkspaceRegistry(desktop, root / "state")

            with self.assertRaises(ValueError):
                registry.attach_workspace("Внешний", outside)

    def test_registry_persists_workspaces(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            desktop = root / "Desktop"
            state = root / "state"
            first = WorkspaceRegistry(desktop, state)
            created = first.create_workspace("Persisted")

            second = WorkspaceRegistry(desktop, state)
            loaded = second.list_workspaces()

            self.assertEqual(len(loaded), 1)
            self.assertEqual(loaded[0]["id"], created["id"])
            self.assertEqual(loaded[0]["name"], "Persisted")


if __name__ == "__main__":
    unittest.main()
