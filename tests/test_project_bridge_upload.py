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


if __name__ == "__main__":
    unittest.main()
