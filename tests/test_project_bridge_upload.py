import base64
import tempfile
import unittest
from pathlib import Path

from project_bridge import ProjectSession


class ProjectBridgeUploadTests(unittest.TestCase):
    def test_save_upload_writes_image_to_vision_folder(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            session = ProjectSession("cifra", tmp)
            saved = session.save_upload(
                "phone photo.png",
                "image/png",
                base64.b64encode(b"image-bytes").decode("ascii"),
            )

            self.assertEqual(saved.parent, Path(tmp) / "vision")
            self.assertTrue(saved.name.startswith("phone_photo_"))
            self.assertEqual(saved.suffix, ".png")
            self.assertEqual(saved.read_bytes(), b"image-bytes")

    def test_save_upload_rejects_empty_payload(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            session = ProjectSession("cifra", tmp)

            with self.assertRaises(ValueError):
                session.save_upload("photo.jpg", "image/jpeg", "")

    def test_broadcast_is_saved_to_current_session_log(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            session = ProjectSession("cifra", tmp)

            session._broadcast("output", "hello from deepseek")

            history = session.load_history(limit=10)
            self.assertEqual(len(history), 1)
            self.assertEqual(history[0]["type"], "output")
            self.assertEqual(history[0]["text"], "hello from deepseek")

    def test_new_session_switches_latest_log(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            session = ProjectSession("cifra", tmp)
            first_id = session.session_id
            session._broadcast("output", "old")

            second_id = session.start_new_session()
            session._broadcast("output", "new")

            self.assertNotEqual(first_id, second_id)
            self.assertEqual(session.load_history(limit=10)[-1]["text"], "new")


if __name__ == "__main__":
    unittest.main()
