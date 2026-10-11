#!/usr/bin/env python3
"""Baixa e prepara o Kokoro v1.0 usado pelo aplicativo.

Os arquivos grandes não são versionados. O script baixa o pacote oficial do
sherpa-onnx, confere o SHA-256 do arquivo compactado e extrai só o necessário
para português brasileiro: o modelo FP32, a tabela de vozes e o subconjunto do
espeak-ng-data usado pelo idioma `pt-br`. Cada arquivo extraído também é
conferido por tamanho e SHA-256, o que permite verificar o bundle sem rede.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tarfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path


ARCHIVE_URL = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
    "tts-models/kokoro-multi-lang-v1_0.tar.bz2"
)
ARCHIVE_SIZE = 349_906_910
ARCHIVE_SHA256 = "c5f7e2d2caf082bc1d20fb70334a61d99d20b484500aad32e7cf84c128ea3298"
ARCHIVE_ROOT = "kokoro-multi-lang-v1_0"


@dataclass(frozen=True)
class Member:
    path: str
    size: int
    sha256: str


# O espeak-ng completo tem 355 arquivos (19 MB). Para `pt-br` bastam as
# tabelas fonéticas, o dicionário e as definições de idioma; a saída do
# Kokoro com este subconjunto é idêntica à obtida com o diretório completo.
MEMBERS = (
    Member(
        "model.onnx",
        325_560_556,
        "b40f62b166ac8164b0627ef48a0b358eda0985e272fb03ef5252e7206305da11",
    ),
    Member(
        "voices.bin",
        28_200_960,
        "1c5a5b983d3d50d8586d437a51f3faa2da7919ce76a013c081e65671a3447c29",
    ),
    Member(
        "tokens.txt",
        687,
        "6ebb6bb288f20f3ae8d004d3c2ca27697da27c037d75e81a60e2a6a663f95425",
    ),
    Member(
        "espeak-ng-data/phondata",
        550_424,
        "4e0288957874029a8c3c9f41a8f517ad4bf18127046decbdd4b9d1d6807ce3a3",
    ),
    Member(
        "espeak-ng-data/phonindex",
        39_074,
        "3ca7b8fa3b42624e4b0f152707e7a39245fce569aa99ea47c055d9e622fcf0c4",
    ),
    Member(
        "espeak-ng-data/phontab",
        55_796,
        "886f3fa402cb0ba73d483aa8ad000af47a6b7cc06293c75a97913fba68a530f6",
    ),
    Member(
        "espeak-ng-data/intonations",
        2_040,
        "3f8af65fd3eda9759a10f021d61361c120871f463515229c925995c7f90918cc",
    ),
    Member(
        "espeak-ng-data/pt_dict",
        67_817,
        "7e8398f15fa4a21db39a213381f28ec0d302b22663c644e865abb61a09c1b004",
    ),
    Member(
        "espeak-ng-data/lang/roa/pt",
        95,
        "a44060072f790e41912c57b7d52f7b6438c4383e0dabdb052f6fdb7aacc23493",
    ),
    Member(
        "espeak-ng-data/lang/roa/pt-BR",
        109,
        "84dd4e34c970fadbe32211eadecfdfaab52432479c0911e43300da88a33398ba",
    ),
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _valid(path: Path, size: int, sha256: str) -> bool:
    return path.is_file() and path.stat().st_size == size and _sha256(path) == sha256


def _invalid_members(output_dir: Path) -> list[str]:
    return [
        member.path
        for member in MEMBERS
        if not _valid(output_dir / member.path, member.size, member.sha256)
    ]


def _download_archive(destination: Path) -> None:
    if _valid(destination, ARCHIVE_SIZE, ARCHIVE_SHA256):
        return

    temporary = destination.with_suffix(f"{destination.suffix}.part")
    temporary.unlink(missing_ok=True)
    print(f"baixando {destination.name} ({ARCHIVE_SIZE / 1_000_000:.1f} MB)")
    request = urllib.request.Request(
        ARCHIVE_URL,
        headers={"User-Agent": "tcc-ela-kokoro-assets/1.0"},
    )
    try:
        with urllib.request.urlopen(request) as response, temporary.open("wb") as target:
            while chunk := response.read(1024 * 1024):
                target.write(chunk)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise

    if not _valid(temporary, ARCHIVE_SIZE, ARCHIVE_SHA256):
        temporary.unlink(missing_ok=True)
        raise RuntimeError(f"tamanho ou SHA-256 inválido para {destination.name}")
    temporary.replace(destination)


def _extract(archive: Path, output_dir: Path) -> None:
    wanted = {f"{ARCHIVE_ROOT}/{member.path}": member for member in MEMBERS}
    with tarfile.open(archive, "r:bz2") as source:
        for info in source:
            member = wanted.pop(info.name, None)
            if member is None:
                continue
            destination = output_dir / member.path
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(f"{destination.name}.part")
            with source.extractfile(info) as data, temporary.open("wb") as target:
                while chunk := data.read(1024 * 1024):
                    target.write(chunk)
            if not _valid(temporary, member.size, member.sha256):
                temporary.unlink(missing_ok=True)
                raise RuntimeError(f"tamanho ou SHA-256 inválido para {member.path}")
            temporary.replace(destination)
            print(f"extraído {member.path}")
    if wanted:
        raise RuntimeError("ausentes no pacote: " + ", ".join(sorted(wanted)))


def _write_manifest(output_dir: Path) -> None:
    manifest = {
        "schema": 2,
        "runtime": "sherpa_onnx 1.13.8",
        "model": "kokoro-multi-lang-v1_0",
        "precision": "fp32",
        "language": "pt-br",
        "source": {"url": ARCHIVE_URL, "sha256": ARCHIVE_SHA256},
        "files": {
            member.path: {"size": member.size, "sha256": member.sha256}
            for member in MEMBERS
        },
    }
    path = output_dir / "manifest.json"
    temporary = path.with_suffix(".json.part")
    temporary.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def _verify(output_dir: Path) -> None:
    problems = _invalid_members(output_dir)
    if not (output_dir / "manifest.json").is_file():
        problems.append("manifest.json")
    if problems:
        raise RuntimeError("arquivos ausentes ou inválidos: " + ", ".join(problems))
    print(f"bundle verificado em {output_dir}")


def main() -> int:
    project_root = Path(__file__).resolve().parent.parent
    default_output = project_root / "assets" / "models" / "kokoro_pt"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=default_output)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    output_dir = args.output.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    if args.verify_only:
        _verify(output_dir)
        return 0

    if args.force or _invalid_members(output_dir):
        archive = output_dir / f"{ARCHIVE_ROOT}.tar.bz2"
        _download_archive(archive)
        _extract(archive, output_dir)
        archive.unlink()
    else:
        print("ok       arquivos já extraídos")
    _write_manifest(output_dir)
    _verify(output_dir)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, tarfile.TarError) as error:
        print(f"erro: {error}", file=sys.stderr)
        raise SystemExit(1)
