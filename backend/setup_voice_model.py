from pathlib import Path

from faster_whisper.utils import download_model


if __name__ == "__main__":
    download_model(
        "base.en",
        revision="3d3d5dee26484f91867d81cb899cfcf72b96be6c",
        output_dir=str(Path(__file__).resolve().parent / "models" / "whisper-base.en"),
    )
